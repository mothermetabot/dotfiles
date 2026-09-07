param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('prepare', 'comment', 'threads', 'reply', 'vote', 'resolve')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'

function Get-GgAdoPat {
    $path = Join-Path $env:LOCALAPPDATA 'gg\ado-pat.txt'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "No Azure DevOps PAT is configured. Run 'gg pr --set-pat'."
    }

    $securePat = $null
    $bstr = [IntPtr]::Zero
    try {
        $encrypted = [System.IO.File]::ReadAllText($path).Trim()
        $securePat = ConvertTo-SecureString $encrypted
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePat)
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
        if ($securePat) { $securePat.Dispose() }
    }
}

function Get-GgAdoHeaders([string]$Pat) {
    $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Pat"))
    @{ Authorization = "Basic $basic"; Accept = 'application/json' }
}

# Azure DevOps puts the useful part of a 400/403 in the RESPONSE BODY, not in
# the exception message. Without this, every failure reads as a bare
# "The remote server returned an error: (400) Bad Request."
function Get-GgAdoErrorInfo($ErrorRecord) {
    $status = 0
    $response = $ErrorRecord.Exception.Response
    if ($response) {
        try { $status = [int]$response.StatusCode } catch { $status = 0 }
    }

    $raw = ''
    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        $raw = [string]$ErrorRecord.ErrorDetails.Message
    }
    elseif ($response) {
        try {
            $stream = $response.GetResponseStream()
            if ($stream) {
                if ($stream.CanSeek) { $stream.Position = 0 }
                $reader = New-Object System.IO.StreamReader($stream)
                try { $raw = $reader.ReadToEnd() } finally { $reader.Dispose() }
            }
        }
        catch { $raw = '' }
    }

    $detail = ''
    if ($raw) {
        try {
            $parsed = $raw | ConvertFrom-Json
            if ($parsed.message) { $detail = [string]$parsed.message }
            elseif ($parsed.value -and $parsed.value.Message) { $detail = [string]$parsed.value.Message }
        }
        catch {
            $detail = $raw
        }
    }
    if (-not $detail) { $detail = [string]$ErrorRecord.Exception.Message }
    $detail = ($detail -replace '\s+', ' ').Trim()
    if ($detail.Length -gt 600) { $detail = $detail.Substring(0, 600) + '...' }

    [pscustomobject]@{ Status = $status; Detail = $detail }
}

function Format-GgAdoError([string]$Operation, $Info) {
    switch ($Info.Status) {
        401 { return "Azure DevOps rejected the PAT (401) while trying to $Operation. It may be expired; run 'gg pr --set-pat'." }
        203 { return "Azure DevOps rejected the PAT (203) while trying to $Operation. It may be expired; run 'gg pr --set-pat'." }
        403 { return "Azure DevOps denied '$Operation' (403). The PAT needs Code (Read & write) and Pull Request Threads (Read & write). Detail: $($Info.Detail)" }
        404 { return "Azure DevOps could not find the resource while trying to $Operation (404). Detail: $($Info.Detail)" }
        default {
            $prefix = if ($Info.Status -gt 0) { "Azure DevOps refused to $Operation (HTTP $($Info.Status))" } else { "Could not $Operation" }
            return "${prefix}: $($Info.Detail)"
        }
    }
}

function Invoke-GgAdoRest([string]$Operation, [string]$Method, [string]$Uri, [hashtable]$Headers, [string]$Json) {
    try {
        if ($PSBoundParameters.ContainsKey('Json') -and $Json) {
            return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers `
                -ContentType 'application/json; charset=utf-8' -Body $Json -ErrorAction Stop
        }
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -ErrorAction Stop
    }
    catch {
        throw (Format-GgAdoError $Operation (Get-GgAdoErrorInfo $_))
    }
}

# Like Invoke-GgAdoRest but returns the failure instead of throwing, so callers
# can retry with a different payload shape.
function Invoke-GgAdoRestTry([string]$Operation, [string]$Method, [string]$Uri, [hashtable]$Headers, [string]$Json) {
    try {
        $data = Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers `
            -ContentType 'application/json; charset=utf-8' -Body $Json -ErrorAction Stop
        [pscustomobject]@{ Ok = $true; Data = $data; Status = 200; Message = '' }
    }
    catch {
        $info = Get-GgAdoErrorInfo $_
        [pscustomobject]@{
            Ok = $false; Data = $null; Status = $info.Status
            Message = (Format-GgAdoError $Operation $info)
        }
    }
}

function Get-GgAdoBaseUrl($Request) {
    $organization = [Uri]::EscapeDataString([string]$Request.organization)
    $project = [Uri]::EscapeDataString([string]$Request.project)
    $repository = [Uri]::EscapeDataString([string]$Request.repositoryId)
    $prId = [int]$Request.pullRequestId
    if (-not $organization -or -not $project -or -not $repository -or $prId -le 0) {
        throw 'The Neovim review request is missing Azure DevOps coordinates.'
    }
    "https://dev.azure.com/$organization/$project/_apis/git/repositories/$repository/pullRequests/$prId"
}

function Get-GgAdoPr($Request, [hashtable]$Headers) {
    $url = "$(Get-GgAdoBaseUrl $Request)?api-version=7.1"
    Invoke-GgAdoRest "read PR !$([int]$Request.pullRequestId)" 'Get' $url $Headers
}

function Assert-GgAdoFresh($Request, $CurrentPr) {
    $prId = [int]$Request.pullRequestId
    if ([string]$CurrentPr.status -ne 'active') {
        throw "PR !$prId is no longer active. Close Neovim and reload the PR list."
    }

    $expected = [string]$Request.expectedSourceCommit
    $actual = [string]$CurrentPr.lastMergeSourceCommit.commitId
    if (-not $expected -or $expected -ne $actual) {
        throw "PR !$prId changed since this review opened. Nothing was submitted; close Neovim and reopen the PR."
    }
}

function Invoke-GgAdoPrepare($Request, [hashtable]$Headers) {
    $current = Get-GgAdoPr $Request $Headers
    Assert-GgAdoFresh $Request $current

    $result = [ordered]@{
        ok = $true
        supportsIterations = [bool]$current.supportsIterations
        iterationId = $null
        changes = @()
        pullRequest = [ordered]@{
            description = [string]$current.description
            mergeStatus = [string]$current.mergeStatus
            mergeFailureType = [string]$current.mergeFailureType
            mergeFailureMessage = [string]$current.mergeFailureMessage
        }
    }

    if (-not $result.supportsIterations) { return $result }

    $baseUrl = Get-GgAdoBaseUrl $Request
    $iterations = Invoke-GgAdoRest 'list PR iterations' 'Get' `
        "$baseUrl/iterations?api-version=7.1" $Headers
    $latest = @($iterations.value) | Sort-Object { [int]$_.id } -Descending | Select-Object -First 1
    if (-not $latest) { throw 'Azure DevOps returned no PR iterations.' }
    if ([string]$latest.sourceRefCommit.commitId -ne [string]$Request.expectedSourceCommit) {
        throw 'The latest Azure DevOps iteration does not match the reviewed source commit.'
    }

    $result.iterationId = [int]$latest.id
    $skip = 0
    do {
        $url = "$baseUrl/iterations/$($result.iterationId)/changes?`$compareTo=0&`$top=2000&`$skip=$skip&api-version=7.1"
        $page = Invoke-GgAdoRest 'list PR iteration changes' 'Get' $url $Headers
        $entries = @($page.changeEntries)
        foreach ($entry in $entries) {
            $result.changes += [ordered]@{
                path = [string]$entry.item.path
                originalPath = [string]$entry.originalPath
                changeTrackingId = [int]$entry.changeTrackingId
            }
        }
        if ([int]$page.nextSkip -gt $skip) { $skip = [int]$page.nextSkip }
        else { $skip = 0 }
    } while ($skip -gt 0)

    $result
}

function Get-GgAdoCommentPosition($Position) {
    if (-not $Position) { return $null }
    [ordered]@{
        line = [int]$Position.line
        offset = [int]$Position.offset
    }
}

function Invoke-GgAdoThreads($Request, [hashtable]$Headers) {
    $url = "$(Get-GgAdoBaseUrl $Request)/threads?api-version=7.1"
    $response = Invoke-GgAdoRest "list comment threads on PR !$([int]$Request.pullRequestId)" 'Get' $url $Headers

    $threads = @()
    foreach ($thread in @($response.value)) {
        if ([bool]$thread.isDeleted) { continue }

        # System comments ("X voted", "refs updated") are kept but flagged:
        # the conversation page shows them, the diff markers skip them.
        $comments = @()
        $hasHumanComment = $false
        foreach ($comment in @($thread.comments)) {
            if ([bool]$comment.isDeleted) { continue }
            $commentType = [string]$comment.commentType
            if ($commentType -ne 'system') { $hasHumanComment = $true }
            $comments += [ordered]@{
                id = [int]$comment.id
                parentCommentId = [int]$comment.parentCommentId
                author = [string]$comment.author.displayName
                content = [string]$comment.content
                publishedDate = [string]$comment.publishedDate
                lastUpdatedDate = [string]$comment.lastUpdatedDate
                commentType = $commentType
                isSystem = ($commentType -eq 'system')
            }
        }
        if ($comments.Count -eq 0) { continue }

        $context = $thread.threadContext
        $entry = [ordered]@{
            id = [int]$thread.id
            status = [string]$thread.status
            isSystem = (-not $hasHumanComment)
            filePath = ''
            rightFileStart = $null
            rightFileEnd = $null
            leftFileStart = $null
            leftFileEnd = $null
            comments = $comments
        }
        if ($context -and $context.filePath) {
            $entry.filePath = ([string]$context.filePath) -replace '^/', ''
            $entry.rightFileStart = Get-GgAdoCommentPosition $context.rightFileStart
            $entry.rightFileEnd = Get-GgAdoCommentPosition $context.rightFileEnd
            $entry.leftFileStart = Get-GgAdoCommentPosition $context.leftFileStart
            $entry.leftFileEnd = Get-GgAdoCommentPosition $context.leftFileEnd
        }
        $threads += $entry
    }

    [ordered]@{ ok = $true; threads = $threads }
}

function Invoke-GgAdoComment($Request, [hashtable]$Headers) {
    if ([string]::IsNullOrWhiteSpace([string]$Request.content)) {
        throw 'The review comment is empty.'
    }

    $current = Get-GgAdoPr $Request $Headers
    Assert-GgAdoFresh $Request $current
    $filePath = ([string]$Request.filePath -replace '\\', '/')
    if (-not $filePath.StartsWith('/')) { $filePath = "/$filePath" }

    # A thread with a filePath but no position is Azure DevOps' file-level
    # comment, shown at the top of the file rather than against a line.
    $fileLevel = [int]$Request.startLine -le 0

    $threadContext = [ordered]@{ filePath = $filePath }
    if (-not $fileLevel) {
        # Neovim sends 0-based UTF-16 offsets; Azure DevOps positions are
        # 1-based (its own threads store offset 1 for a line's first
        # character, and offset 0 is rejected).
        $startOffset = [Math]::Max(1, [int]$Request.startOffset + 1)
        $endOffset = [Math]::Max(1, [int]$Request.endOffset + 1)
        $startLine = [Math]::Max(1, [int]$Request.startLine)
        $endLine = [Math]::Max($startLine, [int]$Request.endLine)
        if ($endLine -eq $startLine -and $endOffset -le $startOffset) {
            $endOffset = $startOffset + 1
        }
        $threadContext.rightFileStart = [ordered]@{ line = $startLine; offset = $startOffset }
        $threadContext.rightFileEnd = [ordered]@{ line = $endLine; offset = $endOffset }
    }

    $body = [ordered]@{
        comments = @([ordered]@{
            parentCommentId = 0
            content = [string]$Request.content
            commentType = 1
        })
        status = 1
        threadContext = $threadContext
    }

    $usedIterations = $false
    if ([bool]$Request.supportsIterations) {
        if ([int]$Request.iterationId -le 0 -or [int]$Request.changeTrackingId -le 0) {
            throw 'Azure DevOps iteration tracking is not ready for this file.'
        }
        $usedIterations = $true
        $body.pullRequestThreadContext = [ordered]@{
            changeTrackingId = [int]$Request.changeTrackingId
            iterationContext = [ordered]@{
                # Equal iteration IDs mean the left side is the common commit,
                # which matches the compareTo=0 changes used for tracking IDs.
                firstComparingIteration = [int]$Request.iterationId
                secondComparingIteration = [int]$Request.iterationId
            }
        }
    }

    $url = "$(Get-GgAdoBaseUrl $Request)/threads?api-version=7.1"
    $operation = if ($fileLevel) { "post a file comment on $filePath" }
                 else { "post an inline comment on $filePath" }
    $attempt = Invoke-GgAdoRestTry $operation 'Post' $url $Headers `
        ($body | ConvertTo-Json -Depth 10 -Compress)

    # The iteration context is the fragile part of the payload (tracking IDs
    # expire as the PR gets pushed to). If it is what Azure DevOps rejected,
    # retry once anchored on the file position alone.
    if (-not $attempt.Ok -and $attempt.Status -eq 400 -and $usedIterations) {
        $fallback = [ordered]@{
            comments = $body.comments
            status = $body.status
            threadContext = $body.threadContext
        }
        $retry = Invoke-GgAdoRestTry $operation 'Post' $url $Headers `
            ($fallback | ConvertTo-Json -Depth 10 -Compress)
        if ($retry.Ok) {
            return [ordered]@{
                ok = $true
                threadId = [int]$retry.Data.id
                commentId = [int](@($retry.Data.comments)[0].id)
                warning = 'Posted without iteration tracking; Azure DevOps rejected the iteration context.'
            }
        }
        throw $attempt.Message
    }

    if (-not $attempt.Ok) { throw $attempt.Message }

    [ordered]@{
        ok = $true
        threadId = [int]$attempt.Data.id
        commentId = [int](@($attempt.Data.comments)[0].id)
    }
}

function Invoke-GgAdoReply($Request, [hashtable]$Headers) {
    if ([string]::IsNullOrWhiteSpace([string]$Request.content)) {
        throw 'The reply is empty.'
    }
    $threadId = [int]$Request.threadId
    if ($threadId -le 0) { throw 'No comment thread was selected for the reply.' }

    $current = Get-GgAdoPr $Request $Headers
    Assert-GgAdoFresh $Request $current

    $body = [ordered]@{
        parentCommentId = [Math]::Max(0, [int]$Request.parentCommentId)
        content = [string]$Request.content
        commentType = 1
    }
    $url = "$(Get-GgAdoBaseUrl $Request)/threads/$threadId/comments?api-version=7.1"
    $comment = Invoke-GgAdoRest "reply to thread $threadId" 'Post' $url $Headers `
        ($body | ConvertTo-Json -Depth 10 -Compress)

    [ordered]@{ ok = $true; threadId = $threadId; commentId = [int]$comment.id }
}

function Invoke-GgAdoResolve($Request, [hashtable]$Headers) {
    $threadId = [int]$Request.threadId
    if ($threadId -le 0) { throw 'No comment thread was selected.' }

    $statusName = [string]$Request.status
    if (-not $statusName) { $statusName = 'fixed' }
    $statusMap = @{ active = 1; fixed = 2; wontfix = 3; closed = 4; bydesign = 5; pending = 6 }
    $statusValue = $statusMap[$statusName.ToLowerInvariant()]
    if (-not $statusValue) { throw "Unknown thread status '$statusName'." }

    $body = [ordered]@{ status = $statusValue }
    $url = "$(Get-GgAdoBaseUrl $Request)/threads/$threadId`?api-version=7.1"
    $thread = Invoke-GgAdoRest "set thread $threadId to $statusName" 'Patch' $url $Headers `
        ($body | ConvertTo-Json -Compress)

    [ordered]@{ ok = $true; threadId = $threadId; status = [string]$thread.status }
}

function Invoke-GgAdoVote($Request, [hashtable]$Headers) {
    $vote = [int]$Request.vote
    if ($vote -notin @(10, 5, 0, -5, -10)) {
        throw "Unsupported Azure DevOps vote value '$vote'."
    }

    $current = Get-GgAdoPr $Request $Headers
    Assert-GgAdoFresh $Request $current

    $organization = [Uri]::EscapeDataString([string]$Request.organization)
    $connection = Invoke-GgAdoRest 'identify the current user' 'Get' `
        "https://dev.azure.com/$organization/_apis/connectionData?connectOptions=1&lastChangeId=-1&lastChangeId64=-1" `
        $Headers
    $reviewerId = [string]$connection.authenticatedUser.id
    if (-not $reviewerId) { throw 'Azure DevOps did not return the authenticated user ID.' }

    $url = "$(Get-GgAdoBaseUrl $Request)/reviewers/$reviewerId`?api-version=7.1"
    $body = [ordered]@{ id = $reviewerId; vote = $vote } | ConvertTo-Json -Compress
    $null = Invoke-GgAdoRest "record your vote on PR !$([int]$Request.pullRequestId)" 'Put' $url $Headers $body

    # Return the refreshed reviewer list so the details pane can update.
    $refreshed = Get-GgAdoPr $Request $Headers
    $reviewers = @(
        foreach ($reviewer in @($refreshed.reviewers)) {
            [ordered]@{
                displayName = [string]$reviewer.displayName
                vote = [int]$reviewer.vote
                isContainer = [bool]$reviewer.isContainer
            }
        }
    )
    [ordered]@{ ok = $true; vote = $vote; reviewers = $reviewers }
}

function Invoke-GgAdoBridge([string]$BridgeAction, $Request) {
    $pat = Get-GgAdoPat
    try {
        $headers = Get-GgAdoHeaders $pat
        switch ($BridgeAction) {
            'prepare' { Invoke-GgAdoPrepare $Request $headers }
            'comment' { Invoke-GgAdoComment $Request $headers }
            'threads' { Invoke-GgAdoThreads $Request $headers }
            'reply'   { Invoke-GgAdoReply $Request $headers }
            'resolve' { Invoke-GgAdoResolve $Request $headers }
            'vote'    { Invoke-GgAdoVote $Request $headers }
        }
    }
    finally {
        $pat = $null
        $headers = $null
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [Console]::InputEncoding = $utf8NoBom
    [Console]::OutputEncoding = $utf8NoBom
    try {
        $raw = [Console]::In.ReadToEnd()
        if ([string]::IsNullOrWhiteSpace($raw)) { throw 'The Neovim bridge received no JSON input.' }
        $request = $raw | ConvertFrom-Json
        $result = Invoke-GgAdoBridge $Action $request
        [Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 10 -Compress))
    }
    catch {
        [Console]::Error.WriteLine($_.Exception.Message)
        exit 1
    }
}
