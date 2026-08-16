@echo off
setlocal enabledelayedexpansion
set DOTFILES=%~dp0

:: 1. ファイルのリンク作成
echo Creating symbolic links...
mklink "%USERPROFILE%\.ideavimrc" "%DOTFILES%.ideavimrc"
mklink "%USERPROFILE%\.gitconfig" "%DOTFILES%.gitconfig"

:: 2. ディレクトリのリンク作成
call :CreateLink "%USERPROFILE%\.ssh" "%DOTFILES%..\.ssh"

:: --- 重要: .wslconfig はリンクではなく「コピー」を行う ---
echo Copying .wslconfig to User Profile...
copy /Y "%DOTFILES%.wslconfig" "%USERPROFILE%\.wslconfig"
echo Setup Completed! Please run "wsl --shutdown" in PowerShell to apply changes.

pause
exit /b

:: --- 関数: ディレクトリのシンボリックリンク作成 ---
:CreateLink
set "LINK_PATH=%~1"
set "TARGET_PATH=%~2"

if not exist "%LINK_PATH%" (
    echo Creating link for %LINK_PATH%...
    mklink /D "%LINK_PATH%" "%TARGET_PATH%"
) else (
    echo %LINK_PATH% already exists. Skipping mklink.
)
goto :eof
