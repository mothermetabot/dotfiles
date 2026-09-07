local M = {}

local api = vim.api
local sessions = {}
local comment_ns = api.nvim_create_namespace 'gg_pr_comments'
local panel_ns = api.nvim_create_namespace 'gg_pr_panel'

local vote_labels = {
  ['10'] = 'approved',
  ['5'] = 'approved with suggestions',
  ['0'] = 'no vote',
  ['-5'] = 'waiting for author',
  ['-10'] = 'rejected',
}

local vote_choices = {
  { label = 'Approve', vote = 10 },
  { label = 'Approve with suggestions', vote = 5 },
  { label = 'Wait for author', vote = -5 },
  { label = 'Reject', vote = -10 },
  { label = 'Reset to no vote', vote = 0 },
}

local resolved_status = { fixed = true, closed = true, wontFix = true, byDesign = true }

local icons = {
  open = vim.g.have_nerd_font and '' or 'C',
  done = vim.g.have_nerd_font and '' or 'v',
  bar = '▏',
}

local function setup_highlights()
  -- `default` so a colorscheme or the user can override these.
  api.nvim_set_hl(0, 'GgPrCommentSign', { link = 'DiagnosticSignInfo', default = true })
  api.nvim_set_hl(0, 'GgPrCommentVirt', { link = 'DiagnosticVirtualTextInfo', default = true })
  api.nvim_set_hl(0, 'GgPrCommentVirtDone', { link = 'Comment', default = true })
  -- Underline rather than a background: the diff panes already own the
  -- background colours, so a region highlight there would be unreadable.
  api.nvim_set_hl(0, 'GgPrCommentRegion', { underline = true, default = true })
end

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = 'gg PR review' })
end

-- Single-key y/n prompt. vim.fn.confirm draws a modal dialog with a button
-- list, which is heavier than this interaction deserves.
local function confirm_yn(prompt)
  api.nvim_echo({ { prompt .. ' ', 'Question' }, { '[y/N]', 'MoreMsg' } }, false, {})
  local ok, char = pcall(vim.fn.getcharstr)
  api.nvim_echo({ { '' } }, false, {})
  vim.cmd.redraw()
  if not ok then
    return false
  end
  return char == 'y' or char == 'Y'
end

local function read_json(path)
  local ok, lines = pcall(vim.fn.readfile, path, 'b')
  if not ok then
    return nil, ('Could not read PR context: %s'):format(lines)
  end
  local decoded_ok, value = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not decoded_ok then
    return nil, ('Could not decode PR context: %s'):format(value)
  end
  return value
end

local function validate_context(ctx)
  local required = {
    'root',
    'organization',
    'project',
    'repositoryId',
    'pullRequestId',
    'sourceCommit',
    'targetCommit',
  }
  for _, key in ipairs(required) do
    if ctx[key] == nil or tostring(ctx[key]) == '' then
      return false, ('PR context is missing %s.'):format(key)
    end
  end
  return true
end

local function current_session()
  local tabpage = api.nvim_get_current_tabpage()
  local session = sessions[tabpage]
  if session and api.nvim_tabpage_is_valid(tabpage) then
    return session
  end
  return nil
end

local function bridge_path()
  return vim.env.GG_ADO_BRIDGE or vim.fs.joinpath(vim.fn.stdpath 'config', 'scripts', 'gg-ado-bridge.ps1')
end

local function powershell_path()
  local system_root = vim.env.SystemRoot or 'C:\\Windows'
  return vim.fs.joinpath(system_root, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
end

local function bridge_command(session, action, values)
  local request = vim.tbl_extend('force', {
    organization = session.ctx.organization,
    project = session.ctx.project,
    repositoryId = session.ctx.repositoryId,
    pullRequestId = session.ctx.pullRequestId,
    expectedSourceCommit = session.ctx.sourceCommit,
  }, values or {})

  local command = {
    powershell_path(),
    '-NoLogo',
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    bridge_path(),
    '-Action',
    action,
  }
  return command, vim.json.encode(request)
end

local function bridge_result(result)
  if result.code ~= 0 then
    local message = vim.trim(result.stderr or '')
    if message == '' then
      message = ('Azure DevOps bridge failed with exit code %d.'):format(result.code)
    end
    return nil, message
  end
  local ok, decoded = pcall(vim.json.decode, result.stdout or '')
  if not ok then
    return nil, ('Invalid response from Azure DevOps bridge: %s'):format(decoded)
  end
  return decoded
end

local function bridge_request(session, action, values, callback)
  local command, stdin = bridge_command(session, action, values)
  vim.system(command, { stdin = stdin, text = true }, vim.schedule_wrap(function(result)
    callback(bridge_result(result))
  end))
end

-- Blocking variant used for every write (comment, reply, resolve, vote) so the
-- caller can close its window on success and keep it open on failure, instead
-- of reporting an error long after the user moved on.
local function bridge_request_sync(session, action, values, timeout)
  local command, stdin = bridge_command(session, action, values)
  local ok, result = pcall(function()
    return vim.system(command, { stdin = stdin, text = true }):wait(timeout or 45000)
  end)
  if not ok then
    return nil, ('Could not run the Azure DevOps bridge: %s'):format(result)
  end
  if result.code == 124 or result.signal == 15 then
    return nil, 'The Azure DevOps request timed out.'
  end
  return bridge_result(result)
end

local function merge_has_error(ctx)
  local status = ctx.mergeStatus or 'not reported'
  local failure_type = ctx.mergeFailureType or 'none'
  local message = ctx.mergeFailureMessage or ''
  return status == 'conflicts'
    or status == 'failure'
    or status == 'rejectedByPolicy'
    or (failure_type ~= '' and failure_type ~= 'none' and failure_type ~= 'notSet')
    or message ~= ''
end

local function first_char(text)
  return vim.fn.strcharpart(text or '', 0, 1)
end

local function initials_of(name)
  name = vim.trim(name or '')
  if name == '' then
    return '??'
  end
  -- Azure DevOps hands out display names as "Lopes, Sergio" here; flip the
  -- Last, First form so the initials still read first-name-first.
  local last, first = name:match '^([^,]+),%s*(.+)$'
  if last and first then
    name = vim.trim(first) .. ' ' .. vim.trim(last)
  end
  local parts = {}
  for word in name:gmatch '[^%s,]+' do
    parts[#parts + 1] = word
  end
  if #parts == 0 then
    return '??'
  end
  if #parts == 1 then
    return vim.fn.strcharpart(parts[1], 0, 2):upper()
  end
  return (first_char(parts[1]) .. first_char(parts[#parts])):upper()
end

local function truncate(text, limit)
  text = vim.trim((text or ''):gsub('%s+', ' '))
  if vim.fn.strchars(text) <= limit then
    return text
  end
  return vim.fn.strcharpart(text, 0, math.max(1, limit - 1)) .. '…'
end

local function normalize_path(path)
  return ((path or ''):gsub('\\', '/'):gsub('^/+', ''))
end

-- Azure DevOps generates threads for votes, policy updates and pushes. They
-- belong on the conversation page but never on the diff.
local function is_system_thread(thread)
  if thread.isSystem ~= nil then
    return thread.isSystem and true or false
  end
  for _, comment in ipairs(thread.comments or {}) do
    if not comment.isSystem then
      return false
    end
  end
  return true
end

local function is_resolved(thread)
  return resolved_status[thread.status or ''] and true or false
end

local function root_comment(thread)
  local comments = thread.comments or {}
  for _, comment in ipairs(comments) do
    if (comment.parentCommentId or 0) == 0 then
      return comment
    end
  end
  return comments[1]
end

local function short_date(value)
  local date = tostring(value or '')
  local stamp = date:match '^(%d%d%d%d%-%d%d%-%d%d)T(%d%d:%d%d)'
  if stamp then
    return (date:match '^(%d%d%d%d%-%d%d%-%d%d)') .. ' ' .. date:match 'T(%d%d:%d%d)'
  end
  return date ~= '' and date or 'unknown date'
end

local function info_lines(session)
  local ctx = session.ctx
  local lines = {
    ('# %s'):format(ctx.title or ('PR !' .. ctx.pullRequestId)),
    '',
    ('**!%s** by **%s**'):format(ctx.pullRequestId, ctx.author or 'unknown'),
    '',
    ('`%s` -> `%s`'):format(ctx.sourceBranch or '?', ctx.targetBranch or '?'),
    '',
    '## Merge',
    '',
    ('- **Status:** `%s`'):format(ctx.mergeStatus or 'not reported'),
  }
  if merge_has_error(ctx) then
    vim.list_extend(lines, {
      ('- **Failure type:** `%s`'):format(ctx.mergeFailureType or 'none'),
      ('- **Message:** %s'):format(ctx.mergeFailureMessage ~= '' and ctx.mergeFailureMessage or 'none'),
    })
  end

  vim.list_extend(lines, { '', '## Reviewers', '' })
  local reviewers = ctx.reviewers or {}
  if #reviewers == 0 then
    table.insert(lines, '_No reviewers_')
  else
    for _, reviewer in ipairs(reviewers) do
      local prefix = reviewer.isContainer and '[group] ' or ''
      table.insert(lines, ('- **%s%s** - %s'):format(
        prefix,
        reviewer.displayName or 'unknown',
        vote_labels[tostring(reviewer.vote or 0)] or ('vote ' .. tostring(reviewer.vote))
      ))
    end
  end

  vim.list_extend(lines, { '', '## Description', '' })
  local description = ctx.description or ''
  if description == '' then
    table.insert(lines, '_No description_')
  else
    vim.list_extend(lines, vim.split(description, '\n', { plain = true }))
  end

  if session.preparing then
    vim.list_extend(lines, { '', '_Loading full Azure DevOps details..._' })
  elseif session.prepare_error then
    vim.list_extend(lines, { '', ('**Azure DevOps:** %s'):format(session.prepare_error) })
  end

  if session.threads then
    local inline = 0
    for _, thread in ipairs(session.threads) do
      if thread.filePath ~= '' then
        inline = inline + 1
      end
    end
    vim.list_extend(lines, { '', ('_%d comment thread(s), %d anchored to files._'):format(#session.threads, inline) })
  end
  return lines
end

local function refresh_info(session)
  if not session.info_buf or not api.nvim_buf_is_valid(session.info_buf) then
    return
  end
  vim.bo[session.info_buf].modifiable = true
  api.nvim_buf_set_lines(session.info_buf, 0, -1, false, info_lines(session))
  vim.bo[session.info_buf].modifiable = false
  vim.bo[session.info_buf].modified = false
end

function M.details()
  local session = current_session()
  if not session then
    notify('This is not a gg PR review tab.', vim.log.levels.WARN)
    return
  end
  if session.info_win and api.nvim_win_is_valid(session.info_win) then
    api.nvim_win_close(session.info_win, true)
    session.info_win = nil
    return
  end

  local buf = api.nvim_create_buf(false, true)
  session.info_buf = buf
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'markdown'
  api.nvim_buf_set_lines(buf, 0, -1, false, info_lines(session))
  vim.bo[buf].modifiable = false

  local width = math.min(100, math.max(54, math.floor(vim.o.columns * 0.72)))
  local height = math.min(#info_lines(session) + 2, math.max(12, math.floor(vim.o.lines * 0.72)))
  session.info_win = api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    border = 'rounded',
    style = 'minimal',
    title = (' PR !%s '):format(session.ctx.pullRequestId),
    title_pos = 'center',
  })
  vim.wo[session.info_win].wrap = true
  vim.wo[session.info_win].conceallevel = 2
  vim.keymap.set('n', 'q', function()
    if api.nvim_win_is_valid(session.info_win) then
      api.nvim_win_close(session.info_win, true)
    end
  end, { buffer = buf, silent = true, desc = 'Close PR details' })
  vim.keymap.set('n', '<leader>rd', M.details, { buffer = buf, silent = true, desc = 'Toggle PR details' })
end

local function utf16_offset(line, byte_index)
  byte_index = math.max(0, math.min(byte_index, #line))
  return vim.str_utfindex(line, 'utf-16', byte_index, false)
end

local function char_end_byte(line, byte_index)
  if byte_index >= #line then
    return #line
  end
  local tail = line:sub(byte_index + 1)
  local char = vim.fn.strcharpart(tail, 0, 1)
  return math.min(#line, byte_index + #char)
end

local function range_from_positions(buf, visual_mode, first, last)
  if visual_mode == '\022' then
    return nil, 'Block selections are not supported for PR comments.'
  end
  if first[2] > last[2] or (first[2] == last[2] and first[3] > last[3]) then
    first, last = last, first
  end
  local start_line = first[2]
  local end_line = last[2]
  local text = api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
  if #text == 0 then
    return nil, 'The selection is empty.'
  end

  if visual_mode == 'V' then
    return {
      startLine = start_line,
      startOffset = 0,
      endLine = end_line,
      endOffset = utf16_offset(text[#text], #text[#text]),
    }
  end

  local start_byte = math.max(0, first[3] - 1)
  local end_byte = math.max(0, last[3] - 1)
  return {
    startLine = start_line,
    startOffset = utf16_offset(text[1], start_byte),
    endLine = end_line,
    endOffset = utf16_offset(text[#text], char_end_byte(text[#text], end_byte)),
  }
end

local function tracking_id_for(session, path)
  if not session.prepare or not session.prepare.supportsIterations then
    return nil
  end
  local normalized = ('/' .. path:gsub('\\', '/')):gsub('^/+', '/')
  for _, change in ipairs(session.prepare.changes or {}) do
    if change.path == normalized or change.originalPath == normalized then
      return change.changeTrackingId
    end
  end
  return nil
end

---------------------------------------------------------------------------
-- Diffview plumbing
---------------------------------------------------------------------------

local function current_diff_target()
  local ok, lib = pcall(require, 'diffview.lib')
  if not ok then
    return nil
  end
  local view = lib.get_current_view()
  if not view or not view.cur_entry then
    return nil
  end
  local entry = view.cur_entry
  local right = entry.layout and entry.layout.b and entry.layout.b.file or nil
  return {
    view = view,
    entry = entry,
    path = entry.path,
    bufnr = right and right.bufnr or nil,
  }
end

local function threads_for_path(session, path)
  if not session.threads or not path then
    return {}
  end
  local wanted = normalize_path(path)
  local lowered = wanted:lower()
  local matches = {}
  for _, thread in ipairs(session.threads) do
    if thread.filePath ~= '' and not is_system_thread(thread) then
      local candidate = normalize_path(thread.filePath)
      if candidate == wanted or candidate:lower() == lowered then
        matches[#matches + 1] = thread
      end
    end
  end
  table.sort(matches, function(a, b)
    local a_line = a.rightFileStart and a.rightFileStart.line or 0
    local b_line = b.rightFileStart and b.rightFileStart.line or 0
    if a_line == b_line then
      return (a.id or 0) < (b.id or 0)
    end
    return a_line < b_line
  end)
  return matches
end

-- Threads on a file, whether anchored to a line or to the file as a whole.
local function counts_for_path(session, path)
  local total, unresolved = 0, 0
  for _, thread in ipairs(threads_for_path(session, path)) do
    total = total + 1
    if not is_resolved(thread) then
      unresolved = unresolved + 1
    end
  end
  return total, unresolved
end

-- Same, aggregated over everything beneath a directory row.
local function counts_for_dir(session, dir_path)
  local prefix = normalize_path(dir_path)
  if prefix ~= '' and not prefix:match '/$' then
    prefix = prefix .. '/'
  end
  local total, unresolved = 0, 0
  for _, thread in ipairs(session.threads or {}) do
    if thread.filePath ~= '' and not is_system_thread(thread) then
      local candidate = normalize_path(thread.filePath)
      if prefix == '' or candidate:sub(1, #prefix):lower() == prefix:lower() then
        total = total + 1
        if not is_resolved(thread) then
          unresolved = unresolved + 1
        end
      end
    end
  end
  return total, unresolved
end

local function count_label(total, unresolved)
  if total == 0 then
    return nil
  end
  if unresolved > 0 and unresolved < total then
    return ('%s %d/%d'):format(icons.open, unresolved, total)
  end
  if unresolved == 0 then
    return ('%s %d'):format(icons.done, total)
  end
  return ('%s %d'):format(icons.open, total)
end

local function thread_range(thread, line_count)
  local start_pos = thread.rightFileStart
  if not start_pos or not start_pos.line then
    return nil
  end
  local start_line = math.min(math.max(start_pos.line, 1), line_count)
  local end_line = start_line
  if thread.rightFileEnd and thread.rightFileEnd.line then
    end_line = math.min(math.max(thread.rightFileEnd.line, start_line), line_count)
  end
  return start_line, end_line
end

-- Root-level comments only: one marker per thread, replies stay hidden until
-- the thread window is opened.
local function render_threads(session, bufnr, path)
  if not bufnr or not api.nvim_buf_is_valid(bufnr) then
    return
  end
  api.nvim_buf_clear_namespace(bufnr, comment_ns, 0, -1)
  local threads = threads_for_path(session, path)
  if #threads == 0 then
    return
  end

  local line_count = api.nvim_buf_line_count(bufnr)
  for _, thread in ipairs(threads) do
    local root = root_comment(thread)
    local start_line, end_line = thread_range(thread, line_count)
    if root and start_line then
      local resolved = is_resolved(thread)
      local replies = math.max(0, #(thread.comments or {}) - 1)
      local label = (' %s %s: %s'):format(
        icons.bar,
        initials_of(root.author),
        truncate(root.content, 58)
      )
      if replies > 0 then
        label = label .. (' (+%d)'):format(replies)
      end
      if resolved then
        label = label .. ' [resolved]'
      end

      local end_text = api.nvim_buf_get_lines(bufnr, end_line - 1, end_line, false)[1] or ''
      api.nvim_buf_set_extmark(bufnr, comment_ns, start_line - 1, 0, {
        end_row = end_line - 1,
        end_col = #end_text,
        hl_group = 'GgPrCommentRegion',
        sign_text = resolved and icons.done or icons.open,
        sign_hl_group = 'GgPrCommentSign',
        virt_text = { { label, resolved and 'GgPrCommentVirtDone' or 'GgPrCommentVirt' } },
        virt_text_pos = 'eol',
        priority = 200,
      })
    end
  end
end

local function render_current(session)
  local target = current_diff_target()
  if target and target.bufnr then
    pcall(render_threads, session, target.bufnr, target.path)
  end
end

---------------------------------------------------------------------------
-- File panel comment counters
---------------------------------------------------------------------------

-- Walks the panel's component tree for the rows it rendered. comp.name,
-- comp.context and comp.lstart are diffview internals (it uses them the same
-- way in file_panel.lua), so every access is guarded: if diffview changes
-- shape the counters just disappear instead of erroring on every render.
local function render_panel_counts(session)
  local panel = session.view and session.view.panel or nil
  if not panel or not panel.bufid or not api.nvim_buf_is_valid(panel.bufid) then
    return
  end
  if not panel.components or not panel.components.comp then
    return
  end

  api.nvim_buf_clear_namespace(panel.bufid, panel_ns, 0, -1)
  if not session.threads then
    return
  end

  local line_count = api.nvim_buf_line_count(panel.bufid)
  panel.components.comp:deep_some(function(comp)
    local context = comp.context
    if not context or type(comp.lstart) ~= 'number' or comp.lstart < 0 then
      return false
    end

    local total, unresolved
    if comp.name == 'file' and context.path then
      total, unresolved = counts_for_path(session, context.path)
    elseif comp.name == 'directory' and context.path and context.collapsed then
      -- Only collapsed directories need a roll-up; an expanded one shows
      -- its files' own counters right below.
      total, unresolved = counts_for_dir(session, context.path)
    else
      return false
    end

    local label = count_label(total, unresolved)
    if label and comp.lstart < line_count then
      api.nvim_buf_set_extmark(panel.bufid, panel_ns, comp.lstart, 0, {
        virt_text = { { label, unresolved > 0 and 'GgPrCommentVirt' or 'GgPrCommentVirtDone' } },
        -- right_align keeps the counter visible in a narrow panel where
        -- long file names would push an eol virt_text out of view.
        virt_text_pos = 'right_align',
        priority = 200,
      })
    end
    return false
  end)
end

-- The panel re-renders on folds, listing-style toggles, colorscheme changes
-- and file-list refreshes, and diffview fires no event for it. Reacting to
-- buffer changes covers every trigger without having to enumerate them.
local function attach_panel_marks(session)
  local panel = session.view and session.view.panel or nil
  if not panel or not panel.bufid or not api.nvim_buf_is_valid(panel.bufid) then
    return
  end
  if session.panel_attached == panel.bufid then
    return
  end
  session.panel_attached = panel.bufid

  api.nvim_buf_attach(panel.bufid, false, {
    on_lines = function()
      if session.panel_pending then
        return
      end
      session.panel_pending = true
      vim.schedule(function()
        session.panel_pending = false
        pcall(render_panel_counts, session)
      end)
    end,
    on_detach = function()
      session.panel_attached = nil
    end,
  })
end

-- Defined with the conversation page below; load_threads refreshes it when
-- it is open so a reply or resolve shows up without reopening.
local refresh_page

local function load_threads(session, callback)
  bridge_request(session, 'threads', nil, function(response, err)
    if err then
      session.threads_error = err
      notify(err, vim.log.levels.ERROR)
      if callback then
        callback(false)
      end
      return
    end
    session.threads_error = nil
    session.threads = response.threads or {}
    render_current(session)
    attach_panel_marks(session)
    pcall(render_panel_counts, session)
    refresh_page(session)
    refresh_info(session)
    if callback then
      callback(true)
    end
  end)
end

---------------------------------------------------------------------------
-- Composer (new comments and replies)
---------------------------------------------------------------------------

local function close_composer(composer)
  if composer.win and api.nvim_win_is_valid(composer.win) then
    api.nvim_win_close(composer.win, true)
  end
  if composer.buf and api.nvim_buf_is_valid(composer.buf) then
    api.nvim_buf_delete(composer.buf, { force = true })
  end
end

-- opts: title, confirm, submit(content) -> ok, message
local function open_composer(opts)
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'markdown'
  api.nvim_buf_set_lines(buf, 0, -1, false, { '' })
  vim.bo[buf].modified = false

  local width = math.min(90, math.max(48, math.floor(vim.o.columns * 0.62)))
  local height = math.min(16, math.max(8, math.floor(vim.o.lines * 0.32)))
  local win = api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    border = 'rounded',
    style = 'minimal',
    title = opts.title,
    title_pos = 'center',
    footer = ' <C-s> submit   q cancel ',
    footer_pos = 'right',
  })
  vim.wo[win].wrap = true
  local composer = { buf = buf, win = win, submitting = false }

  local function submit()
    if composer.submitting then
      return
    end
    local content = vim.trim(table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), '\n'))
    if content == '' then
      notify('Comment is empty.', vim.log.levels.WARN)
      return
    end
    if not confirm_yn(opts.confirm) then
      notify('Nothing was posted.')
      return
    end

    composer.submitting = true
    api.nvim_echo({ { 'Posting to Azure DevOps...', 'MoreMsg' } }, false, {})
    local ok, message = opts.submit(content)
    api.nvim_echo({ { '' } }, false, {})
    composer.submitting = false

    if not ok then
      -- Leave the window open with the text intact so it can be retried.
      notify(message, vim.log.levels.ERROR)
      return
    end
    close_composer(composer)
    notify(message)
  end

  vim.keymap.set({ 'n', 'i' }, '<C-s>', submit, { buffer = buf, silent = true, desc = 'Post to Azure DevOps' })
  vim.keymap.set('n', 'q', function()
    if not vim.bo[buf].modified or confirm_yn 'Discard this draft?' then
      close_composer(composer)
    end
  end, { buffer = buf, silent = true, desc = 'Cancel' })
  vim.cmd.startinsert()
  return composer
end

---------------------------------------------------------------------------
-- Thread window
---------------------------------------------------------------------------

local function thread_lines(thread)
  local location = thread.filePath ~= '' and thread.filePath or 'pull request'
  if thread.rightFileStart and thread.rightFileStart.line then
    local start_line = thread.rightFileStart.line
    local end_line = thread.rightFileEnd and thread.rightFileEnd.line or start_line
    if end_line ~= start_line then
      location = ('%s:%d-%d'):format(location, start_line, end_line)
    else
      location = ('%s:%d'):format(location, start_line)
    end
  end

  local lines = {
    ('# Thread #%s - %s'):format(thread.id, thread.status or 'unknown'),
    '',
    ('`%s`'):format(location),
    '',
  }
  for index, comment in ipairs(thread.comments or {}) do
    if index > 1 then
      table.insert(lines, '')
    end
    table.insert(lines, ('## %s (%s) - %s'):format(
      comment.author or 'unknown',
      initials_of(comment.author),
      short_date(comment.publishedDate)
    ))
    table.insert(lines, '')
    vim.list_extend(lines, vim.split(comment.content or '', '\n', { plain = true }))
  end
  vim.list_extend(lines, { '', '---', '', '_r/<CR>: reply    R: resolve    q: close_' })
  return lines
end

local function open_thread_window(session, thread)
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'markdown'
  local lines = thread_lines(thread)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local width = math.min(100, math.max(54, math.floor(vim.o.columns * 0.68)))
  local height = math.min(#lines + 2, math.max(12, math.floor(vim.o.lines * 0.7)))
  local win = api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    border = 'rounded',
    style = 'minimal',
    title = (' Thread #%s '):format(thread.id),
    title_pos = 'center',
  })
  vim.wo[win].wrap = true
  vim.wo[win].conceallevel = 2

  -- Closing returns to the conversation page when the thread was opened from
  -- it, so q reads as "back" rather than "quit".
  local function close()
    if api.nvim_win_is_valid(win) then
      api.nvim_win_close(win, true)
    end
    local page = session.page
    if page and page.win and api.nvim_win_is_valid(page.win) then
      pcall(api.nvim_set_current_win, page.win)
    end
  end

  local function reply()
    local root = root_comment(thread)
    close()
    open_composer {
      title = (' Reply to thread #%s '):format(thread.id),
      confirm = ('Post reply to thread #%s?'):format(thread.id),
      submit = function(content)
        local response, err = bridge_request_sync(session, 'reply', {
          threadId = thread.id,
          parentCommentId = root and root.id or 0,
          content = content,
        })
        if err then
          return false, err
        end
        load_threads(session)
        return true, ('Reply posted to thread #%s.'):format(response.threadId or thread.id)
      end,
    }
  end

  local function resolve()
    if not confirm_yn(('Resolve thread #%s?'):format(thread.id)) then
      notify 'Thread unchanged.'
      return
    end
    api.nvim_echo({ { 'Resolving thread...', 'MoreMsg' } }, false, {})
    local response, err = bridge_request_sync(session, 'resolve', {
      threadId = thread.id,
      status = 'fixed',
    })
    api.nvim_echo({ { '' } }, false, {})
    if err then
      notify(err, vim.log.levels.ERROR)
      return
    end
    close()
    load_threads(session)
    notify(('Thread #%s is now %s.'):format(thread.id, response.status or 'fixed'))
  end

  vim.keymap.set('n', 'q', close, { buffer = buf, silent = true, desc = 'Close thread' })
  vim.keymap.set('n', 'r', reply, { buffer = buf, silent = true, desc = 'Reply to thread' })
  vim.keymap.set('n', '<CR>', reply, { buffer = buf, silent = true, desc = 'Reply to thread' })
  vim.keymap.set('n', 'R', resolve, { buffer = buf, silent = true, desc = 'Resolve thread' })
end

---------------------------------------------------------------------------
-- Conversation page: every thread, system ones included, root comments only
---------------------------------------------------------------------------

local function page_content(session)
  local threads = session.threads or {}
  local ctx = session.ctx
  local lines = {
    ('# %s'):format(ctx.title or ('PR !' .. ctx.pullRequestId)),
    '',
    ('**!%s** by **%s** - `%s` -> `%s`'):format(
      ctx.pullRequestId,
      ctx.author or 'unknown',
      ctx.sourceBranch or '?',
      ctx.targetBranch or '?'
    ),
    '',
  }

  local votes = {}
  for _, reviewer in ipairs(ctx.reviewers or {}) do
    local prefix = reviewer.isContainer and '[group] ' or ''
    votes[#votes + 1] = ('%s%s: %s'):format(
      prefix,
      reviewer.displayName or 'unknown',
      vote_labels[tostring(reviewer.vote or 0)] or 'unknown'
    )
  end
  if #votes > 0 then
    lines[#lines + 1] = ('**Votes:** %s'):format(table.concat(votes, ' | '))
    lines[#lines + 1] = ''
  end
  lines[#lines + 1] = '---'
  lines[#lines + 1] = ''

  -- Threads oldest first; Azure DevOps ids are chronological.
  local ordered = vim.deepcopy(threads)
  table.sort(ordered, function(a, b)
    return (a.id or 0) < (b.id or 0)
  end)

  local ranges = {}
  if #ordered == 0 then
    lines[#lines + 1] = '_No comments on this pull request yet._'
    return lines, ranges
  end

  for _, thread in ipairs(ordered) do
    local root = root_comment(thread)
    if root then
      local system = is_system_thread(thread)
      local start_line = #lines + 1

      local where = ''
      if thread.filePath ~= '' then
        if thread.rightFileStart and thread.rightFileStart.line then
          where = (' - `%s:%d`'):format(thread.filePath, thread.rightFileStart.line)
        else
          where = (' - `%s` (file)'):format(thread.filePath)
        end
      end

      local tag = system and '[system]' or ('#' .. tostring(thread.id))
      local replies = math.max(0, #(thread.comments or {}) - 1)
      local meta = ('%s %s - %s%s'):format(
        tag,
        root.author or 'unknown',
        short_date(root.publishedDate),
        where
      )
      if not system then
        if replies > 0 then
          meta = meta .. (' - %d repl%s'):format(replies, replies == 1 and 'y' or 'ies')
        end
        if is_resolved(thread) then
          meta = meta .. ' - resolved'
        end
      end

      lines[#lines + 1] = ('## %s'):format(meta)
      lines[#lines + 1] = ''
      -- Root comment only. Replies live behind <leader>rt.
      vim.list_extend(lines, vim.split(root.content or '', '\n', { plain = true }))
      lines[#lines + 1] = ''

      ranges[#ranges + 1] = {
        start_line = start_line,
        end_line = #lines,
        thread = thread,
        system = system,
      }
    end
  end

  vim.list_extend(lines, { '---', '', '_<leader>rt: open thread    q: close_' })
  return lines, ranges
end

refresh_page = function(session)
  local page = session.page
  if not page or not page.buf or not api.nvim_buf_is_valid(page.buf) then
    return
  end
  local lines, ranges = page_content(session)
  page.ranges = ranges
  vim.bo[page.buf].modifiable = true
  api.nvim_buf_set_lines(page.buf, 0, -1, false, lines)
  vim.bo[page.buf].modifiable = false
  vim.bo[page.buf].modified = false
end

local function page_thread_at_cursor(session)
  local page = session.page
  if not page or not page.ranges then
    return nil
  end
  local lnum = api.nvim_win_get_cursor(0)[1]
  for _, range in ipairs(page.ranges) do
    if lnum >= range.start_line and lnum <= range.end_line then
      return range.thread, range.system
    end
  end
  return nil
end

function M.page()
  local session = current_session()
  if not session then
    notify('This is not a gg PR review tab.', vim.log.levels.WARN)
    return
  end
  if not session.threads then
    notify('Comments are still loading.', vim.log.levels.WARN)
    return
  end

  if session.page and session.page.win and api.nvim_win_is_valid(session.page.win) then
    api.nvim_set_current_win(session.page.win)
    return
  end

  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'markdown'

  local width = math.min(120, math.max(60, math.floor(vim.o.columns * 0.8)))
  local height = math.max(15, math.floor(vim.o.lines * 0.85))
  local win = api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    border = 'rounded',
    style = 'minimal',
    title = (' PR !%s conversation '):format(session.ctx.pullRequestId),
    title_pos = 'center',
  })
  vim.wo[win].wrap = true
  vim.wo[win].conceallevel = 2
  vim.wo[win].cursorline = true

  session.page = { buf = buf, win = win, ranges = {} }
  refresh_page(session)

  vim.keymap.set('n', 'q', function()
    if api.nvim_win_is_valid(win) then
      api.nvim_win_close(win, true)
    end
    session.page = nil
  end, { buffer = buf, silent = true, desc = 'Close PR conversation' })
  vim.keymap.set('n', '<leader>rp', function()
    if api.nvim_win_is_valid(win) then
      api.nvim_win_close(win, true)
    end
    session.page = nil
  end, { buffer = buf, silent = true, desc = 'Toggle PR conversation' })

  -- The diffview keymaps are buffer-local to its own buffers, so the page
  -- needs its own binding to drill into a thread.
  local open_thread = function()
    M.thread()
  end
  vim.keymap.set('n', '<leader>rt', open_thread, { buffer = buf, silent = true, desc = 'Open thread under cursor' })
  vim.keymap.set('n', '<CR>', open_thread, { buffer = buf, silent = true, desc = 'Open thread under cursor' })
end

local function pick_thread(session, threads, prompt)
  if #threads == 1 then
    open_thread_window(session, threads[1])
    return
  end
  vim.ui.select(threads, {
    prompt = prompt,
    format_item = function(thread)
      local root = root_comment(thread)
      local line = thread.rightFileStart and thread.rightFileStart.line or 0
      return ('L%d  %s: %s'):format(
        line,
        initials_of(root and root.author),
        truncate(root and root.content, 60)
      )
    end,
  }, function(choice)
    if choice then
      open_thread_window(session, choice)
    end
  end)
end

function M.thread()
  local session = current_session()
  if not session then
    notify('This is not a gg PR review tab.', vim.log.levels.WARN)
    return
  end
  if not session.threads then
    notify('Comment threads are still loading.', vim.log.levels.WARN)
    return
  end

  -- On the conversation page the thread comes from the cursor's entry rather
  -- than from a line anchor in a diff buffer.
  local page = session.page
  if page and page.buf and api.nvim_get_current_buf() == page.buf then
    local thread, system = page_thread_at_cursor(session)
    if not thread then
      notify('No comment thread under the cursor.', vim.log.levels.WARN)
    elseif system then
      notify('That is an Azure DevOps system message; there is nothing to reply to.')
    else
      open_thread_window(session, thread)
    end
    return
  end

  local target = current_diff_target()
  if not target then
    notify('Open a file in the Diffview panes first.', vim.log.levels.WARN)
    return
  end

  local threads = threads_for_path(session, target.path)
  if #threads == 0 then
    notify('No comment threads on this file.')
    return
  end

  -- Prefer the thread under the cursor; fall back to picking from the file.
  local lnum = api.nvim_win_get_cursor(0)[1]
  local hits = {}
  for _, thread in ipairs(threads) do
    local start_pos = thread.rightFileStart
    if start_pos and start_pos.line then
      local start_line = start_pos.line
      local end_line = thread.rightFileEnd and thread.rightFileEnd.line or start_line
      if lnum >= start_line and lnum <= math.max(start_line, end_line) then
        hits[#hits + 1] = thread
      end
    end
  end

  if #hits > 0 then
    pick_thread(session, hits, 'Threads on this line')
  else
    pick_thread(session, threads, ('Threads in %s'):format(target.path))
  end
end

-- Whole-line range for commenting without a selection.
local function line_range(buf, lnum)
  local text = api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ''
  return {
    startLine = lnum,
    startOffset = 0,
    endLine = lnum,
    endOffset = utf16_offset(text, #text),
  }
end

-- location.startLine == 0 means a file-level thread; the bridge then omits
-- the position and Azure DevOps shows it at the top of the file.
local function open_comment_composer(session, location, label)
  if session.prepare and session.prepare.supportsIterations and not location.changeTrackingId then
    notify('Azure DevOps did not return iteration tracking for this file.', vim.log.levels.ERROR)
    return
  end

  open_composer {
    title = (' Comment on %s '):format(label),
    confirm = ('Post comment on %s?'):format(label),
    submit = function(content)
      local response, err = bridge_request_sync(session, 'comment', vim.tbl_extend('force', location, {
        content = content,
        supportsIterations = session.prepare and session.prepare.supportsIterations or false,
        iterationId = session.prepare and session.prepare.iterationId or nil,
      }))
      if err then
        return false, err
      end
      load_threads(session)
      local message = ('Comment posted (thread #%s).'):format(response.threadId or '?')
      if response.warning then
        message = message .. ' ' .. response.warning
      end
      return true, message
    end,
  }
end

function M.comment()
  local session = current_session()
  if not session then
    notify('This is not a gg PR review tab.', vim.log.levels.WARN)
    return
  end
  if session.preparing then
    notify('Azure DevOps iteration data is still loading.', vim.log.levels.WARN)
    return
  end
  if session.prepare_error then
    notify(session.prepare_error, vim.log.levels.ERROR)
    return
  end

  local current_buf = api.nvim_get_current_buf()

  -- In the file panel: comment on the file under the cursor as a whole.
  local panel = session.view and session.view.panel or nil
  if panel and panel.bufid and current_buf == panel.bufid then
    local ok, item = pcall(function()
      return panel:get_item_at_cursor()
    end)
    if not ok or not item or not item.path then
      notify('Put the cursor on a file in the panel.', vim.log.levels.WARN)
      return
    end
    -- DirData carries a path too; diffview itself tells them apart by the
    -- boolean `collapsed` field.
    if type(item.collapsed) == 'boolean' then
      notify('That row is a directory. Put the cursor on a file.', vim.log.levels.WARN)
      return
    end

    open_comment_composer(session, {
      filePath = item.path,
      changeTrackingId = tracking_id_for(session, item.path),
      startLine = 0,
      startOffset = 0,
      endLine = 0,
      endOffset = 0,
    }, ('%s (whole file)'):format(item.path))
    return
  end

  -- Otherwise the cursor has to be in the right/source diff pane.
  local target = current_diff_target()
  if not target or target.bufnr ~= current_buf or target.entry.path == 'null' then
    notify('Put the cursor in the right/source Diffview pane, or on a file in the panel.', vim.log.levels.WARN)
    return
  end

  local mode = vim.fn.mode()
  local range, err
  if mode == 'v' or mode == 'V' or mode == '\022' then
    range, err = range_from_positions(current_buf, mode, vim.fn.getpos 'v', vim.fn.getpos '.')
    -- Leave visual mode so the composer opens on a clean state.
    api.nvim_feedkeys(api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
  else
    -- No selection: comment on the line under the cursor.
    range = line_range(current_buf, api.nvim_win_get_cursor(0)[1])
  end
  if not range then
    notify(err, vim.log.levels.WARN)
    return
  end

  local label = range.startLine == range.endLine
      and ('%s:%d'):format(target.entry.path, range.startLine)
    or ('%s:%d-%d'):format(target.entry.path, range.startLine, range.endLine)

  open_comment_composer(session, vim.tbl_extend('force', range, {
    filePath = target.entry.path,
    changeTrackingId = tracking_id_for(session, target.entry.path),
  }), label)
end

function M.vote()
  local session = current_session()
  if not session then
    notify('This is not a gg PR review tab.', vim.log.levels.WARN)
    return
  end

  vim.ui.select(vote_choices, {
    prompt = ('Vote on PR !%s'):format(session.ctx.pullRequestId),
    format_item = function(choice)
      return choice.label
    end,
  }, function(choice)
    if not choice then
      return
    end
    if not confirm_yn(('%s PR !%s?'):format(choice.label, session.ctx.pullRequestId)) then
      notify 'Vote unchanged.'
      return
    end
    api.nvim_echo({ { 'Recording vote...', 'MoreMsg' } }, false, {})
    local response, err = bridge_request_sync(session, 'vote', { vote = choice.vote })
    api.nvim_echo({ { '' } }, false, {})
    if err then
      notify(err, vim.log.levels.ERROR)
      return
    end
    if response.reviewers then
      session.ctx.reviewers = response.reviewers
      refresh_info(session)
    end
    notify(('%s recorded on PR !%s.'):format(choice.label, session.ctx.pullRequestId))
  end)
end

---------------------------------------------------------------------------
-- Help
---------------------------------------------------------------------------

local help_keys = {
  { '<leader>rd', 'anywhere', 'PR details (toggle)' },
  { '<leader>rp', 'anywhere', 'Conversation page' },
  { '<leader>rt', 'diff, page', 'Open thread under cursor' },
  { '<leader>rc', 'right pane', 'Comment: selection, or cursor line' },
  { '<leader>rc', 'file panel', 'Comment on the whole file' },
  { '<leader>rv', 'anywhere', 'Vote: approve / reject / ...' },
  { '<leader>rr', 'anywhere', 'Reload comment threads' },
  { '<leader>rh', 'anywhere', 'This help' },
  { 'q', 'gg windows', 'Close (thread returns to page)' },
  { '<CR> or r', 'thread view', 'Reply to the thread' },
  { 'R', 'thread view', 'Resolve the thread' },
  { '<C-s>', 'composer', 'Submit the comment' },
}

-- Keys first, then the notes. Kept deliberately short; the notes body is
-- asserted under 2000 characters by the tests.
local function help_lines(session)
  local lines = {
    ('# gg PR review - !%s'):format(session.ctx.pullRequestId),
    '',
    '| Key | Where | Action |',
    '| --- | --- | --- |',
  }
  for _, row in ipairs(help_keys) do
    lines[#lines + 1] = ('| `%s` | %s | %s |'):format(row[1], row[2], row[3])
  end

  local notes = {
    '## Notes',
    '',
    "**Markers** Each root comment shows in the right pane as a sign, an underlined region over the commented lines, and end-of-line text with the author's initials and a snippet. `(+n)` counts replies, `[resolved]` means closed. File comments have no line, so they only show in the panel count.",
    '',
    '**Panel** The counter per file is `unresolved/total`, or a bare count with a check when all are resolved. Collapsed directories roll up the files beneath them.',
    '',
    '**Posting** Every submit asks `[y/N]`, then waits for Azure DevOps. On success the window closes and markers reload; on failure it stays open with your text so you can retry. Errors quote the real Azure DevOps message.',
    '',
    '**Threads** Only comments with a human author can be replied to. System messages (votes, policy, pushes) appear on the conversation page only.',
    '',
    '**Safety** If the PR gets new commits after this review opened, submissions are refused rather than pinned to stale lines. Close and reopen it.',
    '',
    '**Exit** `q` closes a gg window. From the diff it closes the review and quits Neovim, since `gg pr` started it just for this PR.',
  }
  vim.list_extend(lines, { '' })
  vim.list_extend(lines, notes)
  return lines, table.concat(notes, '\n')
end

function M.help()
  local session = current_session()
  if not session then
    notify('This is not a gg PR review tab.', vim.log.levels.WARN)
    return
  end
  if session.help_win and api.nvim_win_is_valid(session.help_win) then
    api.nvim_win_close(session.help_win, true)
    session.help_win = nil
    return
  end

  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'markdown'
  local lines = help_lines(session)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local width = math.min(88, math.max(60, math.floor(vim.o.columns * 0.7)))
  local height = math.min(#lines + 2, math.max(20, math.floor(vim.o.lines * 0.8)))
  session.help_win = api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    border = 'rounded',
    style = 'minimal',
    title = ' gg PR review keys ',
    title_pos = 'center',
  })
  vim.wo[session.help_win].wrap = true
  vim.wo[session.help_win].conceallevel = 2

  local function close()
    if session.help_win and api.nvim_win_is_valid(session.help_win) then
      api.nvim_win_close(session.help_win, true)
    end
    session.help_win = nil
  end
  vim.keymap.set('n', 'q', close, { buffer = buf, silent = true, desc = 'Close help' })
  vim.keymap.set('n', '<leader>rh', close, { buffer = buf, silent = true, desc = 'Toggle help' })
end

function M.refresh()
  local session = current_session()
  if not session then
    notify('This is not a gg PR review tab.', vim.log.levels.WARN)
    return
  end
  notify 'Refreshing comment threads...'
  load_threads(session, function(ok)
    if ok then
      notify(('%d comment thread(s) loaded.'):format(#(session.threads or {})))
    end
  end)
end

local function prepare(session)
  session.preparing = true
  bridge_request(session, 'prepare', nil, function(response, err)
    session.preparing = false
    if err then
      session.prepare_error = err
      refresh_info(session)
      notify(err, vim.log.levels.ERROR)
      return
    end
    session.prepare = response
    local current = response.pullRequest or {}
    if current.description ~= nil then
      session.ctx.description = current.description
    end
    if current.mergeStatus ~= nil and current.mergeStatus ~= '' then
      session.ctx.mergeStatus = current.mergeStatus
    end
    session.ctx.mergeFailureType = current.mergeFailureType or session.ctx.mergeFailureType
    session.ctx.mergeFailureMessage = current.mergeFailureMessage or session.ctx.mergeFailureMessage
    refresh_info(session)
  end)
end

local function attach_autocmds(session, tabpage)
  local group = api.nvim_create_augroup('GgPrReview' .. tabpage, { clear = true })
  -- Diffview builds each file's buffers lazily, so markers have to be drawn
  -- when a diff buffer enters a window rather than once up front.
  api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'DiffviewDiffBufWinEnter',
    callback = function()
      if api.nvim_get_current_tabpage() == tabpage then
        vim.schedule(function()
          render_current(session)
        end)
      end
    end,
  })
  -- DiffviewViewClosed carries no payload saying which view closed. Testing
  -- lib.views membership does not work: View:close() tabcloses and emits but
  -- leaves the view registered (only the scheduled dispose_stray_views
  -- removes it). The tabpage is already gone by emit time, so its validity
  -- is the reliable signal that the view that closed was ours.
  api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'DiffviewViewClosed',
    callback = function()
      if api.nvim_tabpage_is_valid(tabpage) then
        return
      end

      local owns_editor = session.owns_editor
      sessions[tabpage] = nil
      pcall(api.nvim_del_augroup_by_id, group)

      -- This Neovim was started by `gg pr` purely to review, so closing the
      -- view should leave the shell rather than an empty buffer. `confirm`
      -- prompts instead of discarding if anything is unsaved.
      if owns_editor then
        vim.schedule(function()
          pcall(vim.cmd, 'confirm qa')
        end)
      end
    end,
  })
end

local function attach_session(ctx, attempt, owns_editor)
  local ok, lib = pcall(require, 'diffview.lib')
  local view = ok and lib.get_current_view() or nil
  if not view then
    if attempt < 20 then
      vim.defer_fn(function()
        attach_session(ctx, attempt + 1, owns_editor)
      end, 25)
    else
      notify('Diffview opened, but gg could not attach the PR review session.', vim.log.levels.ERROR)
    end
    return
  end
  local session = { ctx = ctx, view = view, owns_editor = owns_editor and true or false }
  sessions[view.tabpage] = session
  setup_highlights()
  attach_autocmds(session, view.tabpage)
  prepare(session)
  load_threads(session)
  notify(('Reviewing PR !%s. <leader>rh for keys.'):format(ctx.pullRequestId))
end

-- opts.owns_editor: this Neovim exists only for the review, so quit when the
-- view closes. Defaults to true because `gg pr` is the only caller.
function M.open(context_path, opts)
  opts = opts or {}
  local owns_editor = opts.owns_editor ~= false
  local ctx, err = read_json(context_path)
  if not ctx then
    notify(err, vim.log.levels.ERROR)
    return
  end
  local valid, validation_error = validate_context(ctx)
  if not valid then
    notify(validation_error, vim.log.levels.ERROR)
    return
  end

  local ok, open_error = pcall(function()
    vim.cmd('cd ' .. vim.fn.fnameescape(ctx.root))
    vim.cmd(('DiffviewOpen %s...%s'):format(ctx.targetCommit, ctx.sourceCommit))
  end)
  if not ok then
    notify(('Could not open PR Diffview: %s'):format(open_error), vim.log.levels.ERROR)
    return
  end
  attach_session(ctx, 1, owns_editor)
end

M._test = {
  count_label = count_label,
  help_keys = help_keys,
  help_lines = help_lines,
  counts_for_dir = counts_for_dir,
  counts_for_path = counts_for_path,
  current_session = current_session,
  info_lines = info_lines,
  initials_of = initials_of,
  is_resolved = is_resolved,
  is_system_thread = is_system_thread,
  line_range = line_range,
  page_content = page_content,
  merge_has_error = merge_has_error,
  normalize_path = normalize_path,
  range_from_positions = range_from_positions,
  render_threads = render_threads,
  root_comment = root_comment,
  short_date = short_date,
  thread_lines = thread_lines,
  threads_for_path = threads_for_path,
  thread_range = thread_range,
  tracking_id_for = tracking_id_for,
  truncate = truncate,
  validate_context = validate_context,
}

return M
