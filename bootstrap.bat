@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "DOTFILES=%~dp0"
if "%DOTFILES:~-1%"=="\" set "DOTFILES=%DOTFILES:~0,-1%"
set "USER_HOME=%USERPROFILE%"
if defined DOTFILES_HOME set "USER_HOME=%DOTFILES_HOME%"
if not "%~1"=="" set "USER_HOME=%~1"

echo [1/4] Checking prerequisites...
where powershell || (
  echo ERROR: powershell is required.
  exit /b 1
)

if not exist "%USER_HOME%" (
  echo Creating "%USER_HOME%"
  mkdir "%USER_HOME%" || (
    echo ERROR: could not create "%USER_HOME%"
    exit /b 1
  )
)
echo Using home path: "%USER_HOME%"

echo [2/4] Installing Scoop (if missing)...
where scoop
if errorlevel 1 (
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force; iwr -useb get.scoop.sh | iex"
  if errorlevel 1 (
    echo ERROR: Scoop installation failed.
    exit /b 1
  )
)

rem Refresh PATH for this cmd session after scoop install.
set "PATH=%USERPROFILE%\scoop\shims;%PATH%"

echo [3/4] Installing packages with Scoop...
call :ensure_scoop_bucket "main" || exit /b 1
call :ensure_scoop_bucket "extras" || exit /b 1
rem Install common Scoop dependencies up front to reduce prompts.
call :install_scoop_pkg "git" || exit /b 1
call :install_scoop_pkg "7zip" || exit /b 1
call :install_scoop_pkg "aria2" || exit /b 1
call :install_scoop_pkg "fzf" || exit /b 1
call :install_scoop_pkg "ripgrep" || exit /b 1
call :install_scoop_pkg "uv" || exit /b 1
call :install_scoop_pkg "neovim" || exit /b 1
call :install_scoop_pkg "starship" || exit /b 1
call :install_scoop_pkg "lazygit" || exit /b 1
call :install_scoop_pkg "komorebi" || exit /b 1

echo [4/4] Creating links and copying config files...

call :ensure_dir "%USERPROFILE%\Documents\WindowsPowerShell" || exit /b 1
call :ensure_dir "%USERPROFILE%\Documents\PowerShell" || exit /b 1
call :ensure_dir "%USERPROFILE%\AppData\Local" || exit /b 1

call :copy_file "%DOTFILES%\.bash_profile" "%USER_HOME%\.bash_profile" || exit /b 1
call :copy_file "%DOTFILES%\.gitconfig" "%USER_HOME%\.gitconfig" || exit /b 1
call :copy_file "%DOTFILES%\.zshrc" "%USER_HOME%\.zshrc" || exit /b 1

call :mk_hardlink "%USER_HOME%\.bashrc" "%DOTFILES%\.bashrc" || exit /b 1
call :mk_hardlink "%USERPROFILE%\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" "%DOTFILES%\.shell\Microsoft.PowerShell_profile.ps1" || exit /b 1
call :mk_hardlink "%USERPROFILE%\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" "%DOTFILES%\.shell\Microsoft.PowerShell_profile.ps1" || exit /b 1

call :mk_junction "%USER_HOME%\.config" "%DOTFILES%\.config" || exit /b 1
call :mk_junction "%USER_HOME%\komorebi" "%DOTFILES%\komorebi" || exit /b 1
call :mk_junction "%USERPROFILE%\AppData\Local\nvim" "%DOTFILES%\.config\nvim" || exit /b 1

echo Setting user-level environment variables for komorebi/whkd...
call :set_system_env "KOMOREBI_CONFIG_HOME" "%DOTFILES%\komorebi" || exit /b 1
call :set_system_env "WHKD_CONFIG_HOME" "%DOTFILES%\komorebi" || exit /b 1

echo.
echo Bootstrap finished.
echo Open a new terminal so PATH changes are picked up.
exit /b 0

:install_scoop_pkg
set "PKG=%~1"
where scoop || (
  echo ERROR: scoop command is unavailable.
  exit /b 1
)

echo Installing %PKG%...
call scoop install %PKG%
if errorlevel 1 (
  echo WARNING: Could not install "%PKG%" from scoop. Continuing...
)
exit /b 0

:ensure_scoop_bucket
set "BUCKET=%~1"
call scoop bucket list | findstr /I /R /C:"^%BUCKET% "
if errorlevel 1 (
  echo Adding scoop bucket "%BUCKET%"...
  call scoop bucket add %BUCKET%
  if errorlevel 1 (
    echo ERROR: Failed to add scoop bucket "%BUCKET%".
    exit /b 1
  )
)
exit /b 0

:ensure_dir
if not exist "%~1" (
  mkdir "%~1"
  if errorlevel 1 (
    echo ERROR: Failed to create directory "%~1"
    exit /b 1
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
  echo ERROR: Failed to copy "%~1" to "%~2"
  exit /b 1
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
    echo ERROR: Could not remove existing file "%LINK%"
    exit /b 1
  )
)

mklink /H "%LINK%" "%TARGET%"
if errorlevel 1 (
  echo ERROR: Failed to create hardlink "%LINK%" -> "%TARGET%"
  exit /b 1
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
  echo ERROR: Failed to create junction "%LINK%" -> "%TARGET%"
  exit /b 1
)
exit /b 0

:set_system_env
set "ENV_NAME=%~1"
set "ENV_VALUE=%~2"
setx %ENV_NAME% "%ENV_VALUE%"
if errorlevel 1 (
  echo WARNING: Failed to set user env var %ENV_NAME%.
  exit /b 0
)
exit /b 0
