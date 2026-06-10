@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM Bootstrap.bat
REM - Runs normal bootstrap steps non-elevated
REM - Only sets SYSTEM-wide env vars elevated (setx /M)
REM ============================================================

REM --- If invoked in "elevated env var setter" mode, do that and exit ---
if /i "%~1"=="--set-system-env" (
  shift /1
  call :set_system_env "%~1" "%~2"
  exit /b %ERRORLEVEL%
)

REM --- Compute paths / inputs ---
set "DOTFILES=%~dp0"
if "%DOTFILES:~-1%"=="\" set "DOTFILES=%DOTFILES:~0,-1%"
set "USER_HOME=%USERPROFILE%"
if defined DOTFILES_HOME set "USER_HOME=%DOTFILES_HOME%"
if not "%~1"=="" set "USER_HOME=%~1"

echo [1/4] Checking prerequisites...
where powershell || (
  set "rc=!errorlevel!"
  call :die !rc! "PowerShell is required but was not found in PATH."
)

if not exist "%USER_HOME%" (
  echo Creating "%USER_HOME%"
  mkdir "%USER_HOME%" || (
    set "rc=!errorlevel!"
    call :die !rc! "Could not create home directory: %USER_HOME%"
  )
)
echo Using home path: "%USER_HOME%"

echo [2/4] Installing Scoop (if missing)...
where scoop
if errorlevel 1 (
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force; iwr -useb get.scoop.sh | iex"
  if errorlevel 1 (
    set "rc=!errorlevel!"
    call :die !rc! "Scoop installation failed. Command: iwr -useb get.scoop.sh | iex"
  )
)

REM Refresh PATH for this cmd session after scoop install.
set "PATH=%USERPROFILE%\scoop\shims;%PATH%"

echo [3/4] Installing packages with Scoop...
call :ensure_scoop_bucket "main" || (set "rc=!errorlevel!" & call :die !rc! "Failed while ensuring scoop bucket 'main'.")
call :ensure_scoop_bucket "extras" || (set "rc=!errorlevel!" & call :die !rc! "Failed while ensuring scoop bucket 'extras'.")

REM Install common Scoop dependencies up front to reduce prompts.
call :install_scoop_pkg "coreutils" || (set "rc=!errorlevel!" & call :die !rc! "Failed during package install step (coreutils).")
call :install_scoop_pkg "zoxide" || (set "rc=!errorlevel!" & call :die !rc! "Failed during package install step (zoxide).")
call :install_scoop_pkg "which" || (set "rc=!errorlevel!" & call :die !rc! "Failed during package install step (which).")
call :install_scoop_pkg "curl" || (set "rc=!errorlevel!" & call :die !rc! "Failed during package install step (curl).")
call :install_scoop_pkg "winget" || (set "rc=!errorlevel!" & call :die !rc! "Failed during package install step (winget).")
call :install_scoop_pkg "git" || (set "rc=!errorlevel!" & call :die !rc! "Failed during package install step (git).")
call :install_scoop_pkg "7zip" || (set "rc=!errorlevel!" & call :die !rc! "Failed during package install step (7zip).")
call :install_scoop_pkg "aria2" || (set "rc=!errorlevel!" & call :die !rc! "Failed during package install step (aria2).")
call :install_scoop_pkg "fzf" || (set "rc=!errorlevel!" & call :die !rc! "Failed during package install step (fzf).")
call :install_scoop_pkg "ripgrep" || (set "rc=!errorlevel!" & call :die !rc! "Failed during package install step (ripgrep).")
call :install_scoop_pkg "uv" || (set "rc=!errorlevel!" & call :die !rc! "Failed during package install step (uv).")
call :install_scoop_pkg "neovim" || (set "rc=!errorlevel!" & call :die !rc! "Failed during package install step (neovim).")
call :install_scoop_pkg "starship" || (set "rc=!errorlevel!" & call :die !rc! "Failed during package install step (starship).")
call :install_scoop_pkg "lazygit" || (set "rc=!errorlevel!" & call :die !rc! "Failed during package install step (lazygit).")
call :install_scoop_pkg "komorebi" || (set "rc=!errorlevel!" & call :die !rc! "Failed during package install step (komorebi).")
call :install_scoop_pkg "whkd" || (set "rc=!errorlevel!" & call :die !rc! "Failed during package install step (whkd).")
call :install_scoop_pkg "flameshot" || (set "rc=!errorlevel!" & call :die !rc! "Failed during package install step (flameshot).")
call :install_scoop_pkg "nodejs" || (set "rc=!errorlevel!" & call :die !rc! "Failed during package install step (nodejs).")
call :install_scoop_pkg "rustup" || (set "rc=!errorlevel!" & call :die !rc! "Failed during package install step (rustup).")
call :install_scoop_pkg "tree-sitter" || (set "rc=!errorlevel!" & call :die !rc! "Failed during package install step (rustup).")

echo Disabling aria2 warning
call scoop config aria2-warning-enabled false
if errorlevel 1 (
  set "rc=!errorlevel!"
  call :die !rc! "Failed to run: scoop config aria2-warning-enabled false"
)

echo Installing MSVC toolchain (this can take several minutes)...
where winget >nul 2>&1
if errorlevel 1 (
  set "rc=!errorlevel!"
  echo WARNING: winget command not found. Skipping MSVC toolchain install. Exit code: !rc!
  goto :after_msvc_install
)

winget install -e --id Microsoft.VisualStudio.2022.BuildTools --accept-source-agreements --accept-package-agreements --disable-interactivity --override "--passive --wait --add Microsoft.VisualStudio.Workload.VCTools;includeRecommended"
set "rc=!errorlevel!"
echo MSVC toolchain installer exit code: !rc!
if "!rc!"=="3010" (
  echo NOTE: Installer requested reboot code 3010. Continuing bootstrap.
  set "rc=0"
)
if errorlevel 1 (
  echo WARNING: Skipping MSVC toolchain install due to winget failure. This can happen when winget is blocked by Group Policy.
  echo WARNING: You can install Microsoft.VisualStudio.2022.BuildTools manually later.
  goto :after_msvc_install
)
echo MSVC toolchain install step completed.
:after_msvc_install

echo [4/4] Creating links and copying config files...

call :ensure_dir "%USERPROFILE%\Documents\WindowsPowerShell" || (set "rc=!errorlevel!" & call :die !rc! "Failed to prepare directory: %USERPROFILE%\Documents\WindowsPowerShell")
call :ensure_dir "%USERPROFILE%\Documents\PowerShell" || (set "rc=!errorlevel!" & call :die !rc! "Failed to prepare directory: %USERPROFILE%\Documents\PowerShell")
call :ensure_dir "%USERPROFILE%\AppData\Local" || (set "rc=!errorlevel!" & call :die !rc! "Failed to prepare directory: %USERPROFILE%\AppData\Local")
call :remove_ps_aliases || (set "rc=!errorlevel!" & call :die !rc! "Failed while removing conflicting PowerShell aliases.")

call :copy_file "%DOTFILES%\.bash_profile" "%USER_HOME%\.bash_profile" || (set "rc=!errorlevel!" & call :die !rc! "Failed to copy .bash_profile")
call :copy_file "%DOTFILES%\.gitconfig" "%USER_HOME%\.gitconfig" || (set "rc=!errorlevel!" & call :die !rc! "Failed to copy .gitconfig")
call :copy_file "%DOTFILES%\.zshrc" "%USER_HOME%\.zshrc" || (set "rc=!errorlevel!" & call :die !rc! "Failed to copy .zshrc")

call :mk_hardlink "%USER_HOME%\.bashrc" "%DOTFILES%\.bashrc" || (set "rc=!errorlevel!" & call :die !rc! "Failed to create hardlink for .bashrc")
call :mk_hardlink "%USERPROFILE%\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" "%DOTFILES%\.shell\Microsoft.PowerShell_profile.ps1" || (set "rc=!errorlevel!" & call :die !rc! "Failed to create WindowsPowerShell profile hardlink")
call :mk_hardlink "%USERPROFILE%\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" "%DOTFILES%\.shell\Microsoft.PowerShell_profile.ps1" || (set "rc=!errorlevel!" & call :die !rc! "Failed to create PowerShell profile hardlink")

call :mk_junction "%USER_HOME%\.config" "%DOTFILES%\.config" || (set "rc=!errorlevel!" & call :die !rc! "Failed to create junction for .config")
call :mk_junction "%USER_HOME%\komorebi" "%DOTFILES%\komorebi" || (set "rc=!errorlevel!" & call :die !rc! "Failed to create junction for komorebi")
call :mk_junction "%USERPROFILE%\AppData\Local\nvim" "%DOTFILES%\.config\nvim" || (set "rc=!errorlevel!" & call :die !rc! "Failed to create junction for nvim config")

echo Setting SYSTEM-level environment variables for komorebi/whkd (will prompt for admin)...
call :elevate_set_system_env "KOMOREBI_CONFIG_HOME" "%DOTFILES%\komorebi" || (set "rc=!errorlevel!" & call :die !rc! "Failed to set system env var KOMOREBI_CONFIG_HOME")
call :elevate_set_system_env "WHKD_CONFIG_HOME" "%DOTFILES%\komorebi" || (set "rc=!errorlevel!" & call :die !rc! "Failed to set system env var WHKD_CONFIG_HOME")

echo.
echo Bootstrap finished.
echo Open a new terminal so PATH changes are picked up.
exit /b 0


:die
set "ERR_CODE=%~1"
if "%ERR_CODE%"=="" set "ERR_CODE=1"
if "%ERR_CODE%"=="0" set "ERR_CODE=1"
echo.
echo [ERROR] %~2
echo [ERROR] Exit code: %ERR_CODE%
echo [ERROR] Bootstrap aborted.
exit /b %ERR_CODE%


:install_scoop_pkg
set "PKG=%~1"
where scoop || (
  set "rc=!errorlevel!"
  echo ERROR: scoop command is unavailable while installing "%PKG%". Exit code: !rc!
  exit /b !rc!
)

echo Installing %PKG%...
call scoop install %PKG%
if errorlevel 1 (
  set "rc=!errorlevel!"
  echo WARNING: Could not install "%PKG%" from scoop. Exit code: !rc!. Continuing...
)
exit /b 0


:ensure_scoop_bucket
set "BUCKET=%~1"
call scoop bucket list | findstr /I /R /C:"^%BUCKET% "
if errorlevel 1 (
  echo Adding scoop bucket "%BUCKET%"...
  call scoop bucket add %BUCKET%
  if errorlevel 1 (
    set "rc=!errorlevel!"
    echo ERROR: Failed to add scoop bucket "%BUCKET%". Exit code: !rc!
    exit /b !rc!
  )
)
exit /b 0


:ensure_dir
if not exist "%~1" (
  mkdir "%~1"
  if errorlevel 1 (
    set "rc=!errorlevel!"
    echo ERROR: Failed to create directory "%~1". Exit code: !rc!
    exit /b !rc!
  )
)
exit /b 0


:copy_file
if not exist "%~1" (
  echo WARNING: Source file missing: "%~1"
  exit /b 0
)
copy /Y "%~1" "%~2"
if errorlevel 1 (
  set "rc=!errorlevel!"
  echo ERROR: Failed to copy "%~1" to "%~2". Exit code: !rc!
  exit /b !rc!
)
exit /b 0


:mk_hardlink
set "LINK=%~1"
set "TARGET=%~2"

if not exist "%TARGET%" (
  echo ERROR: Hardlink target missing: "%TARGET%"
  exit /b 1
)

if exist "%LINK%" (
  del /F /Q "%LINK%"
  if exist "%LINK%" (
    echo ERROR: Could not remove existing file "%LINK%".
    exit /b 1
  )
)

mklink /H "%LINK%" "%TARGET%"
if errorlevel 1 (
  set "rc=!errorlevel!"
  echo ERROR: Failed to create hardlink "%LINK%" -> "%TARGET%". Exit code: !rc!
  exit /b !rc!
)
exit /b 0


:mk_junction
set "LINK=%~1"
set "TARGET=%~2"

if not exist "%TARGET%" (
  echo ERROR: Junction target missing: "%TARGET%"
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p='%LINK%'; if(Test-Path -LiteralPath $p){ Remove-Item -LiteralPath $p -Recurse -Force }"
if exist "%LINK%" (
  echo ERROR: Could not remove existing path "%LINK%"
  exit /b 1
)

mklink /J "%LINK%" "%TARGET%"
if errorlevel 1 (
  set "rc=!errorlevel!"
  echo ERROR: Failed to create junction "%LINK%" -> "%TARGET%". Exit code: !rc!
  exit /b !rc!
)
exit /b 0


REM --- runs ONLY the system env var set in an elevated cmd instance ---
:elevate_set_system_env
set "ENV_NAME=%~1"
set "ENV_VALUE=%~2"

REM Relaunch just this batch label elevated via PowerShell UAC prompt
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process cmd -Verb RunAs -ArgumentList '/c','\"%~f0\" --set-system-env \"%ENV_NAME%\" \"%ENV_VALUE%\"' -Wait"
if errorlevel 1 (
  set "rc=!errorlevel!"
  echo ERROR: Failed to elevate and set system env var %ENV_NAME%. Exit code: !rc!
  exit /b !rc!
)
exit /b 0


:set_system_env
set "ENV_NAME=%~1"
set "ENV_VALUE=%~2"
setx "%ENV_NAME%" "%ENV_VALUE%" /M
if errorlevel 1 (
  set "rc=!errorlevel!"
  echo ERROR: Failed to set system env var %ENV_NAME%. Exit code: !rc!
  exit /b !rc!
)
exit /b 0


:remove_ps_aliases
echo Removing PowerShell aliases for common Unix commands...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$aliases = 'ls','cat','pwd','rm','mv','cp','mkdir','rmdir','touch','man','wget','curl','grep','sed','awk';" ^
  "foreach($a in $aliases){ Remove-Item -Path (\"Alias:$a\") -ErrorAction SilentlyContinue }"
if errorlevel 1 (
  echo WARNING: Failed to remove one or more PowerShell aliases.
  exit /b 0
)
exit /b 0
