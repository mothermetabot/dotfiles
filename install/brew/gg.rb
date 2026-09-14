# Homebrew formula for gg, installed from the prebuilt release rather than
# built from source - the release ships a static x86_64 binary, so there is no
# reason to pull in a Rust toolchain.
#
# Install:
#   brew install --formula ~/.dotfiles/install/brew/gg.rb
#
# A local formula path avoids needing a tap. If you ever want `brew install gg`
# to work unqualified, move this file to a repo named homebrew-<something> under
# Formula/ and `brew tap mothermetabot/<something>`.
#
# The Windows counterpart is ../scoop/gg.json.

class Gg < Formula
  desc "fzf-driven git helper: branches, changes, stashes, worktrees, commits, PRs"
  homepage "https://github.com/mothermetabot/gg"
  url "https://github.com/mothermetabot/gg/releases/download/v0.1.1/gg-0.1.1-x86_64-unknown-linux-gnu.tar.gz"
  sha256 "9cf668dd44162fb812e0d4b487402d47bc192cdd0070fb4bec090a39dc3875bf"
  version "0.1.1"
  license "MIT"

  # Only a linux-gnu x86_64 asset is published. Without this, brew on macOS or
  # on arm64 would download a binary it cannot run and fail confusingly.
  depends_on :linux
  depends_on arch: :x86_64

  # gg shells out to both of these for every picker.
  depends_on "fzf"
  depends_on "git"

  def install
    bin.install "gg"

    # The archive also ships the Neovim side of the PR picker. Install it where
    # a plugin manager can find it; it is not wired into .config/nvim.
    (pkgshare/"nvim").install Dir["nvim/*"] if Dir.exist?("nvim")
  end

  def caveats
    <<~EOS
      The Neovim half of the PR picker was installed to:
        #{pkgshare}/nvim
      It is not loaded automatically - point your plugin loader at that path.
    EOS
  end

  test do
    assert_match "gg", shell_output("#{bin}/gg --version")
  end
end
