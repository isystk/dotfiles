@echo off
setlocal enabledelayedexpansion
set DOTFILES=%~dp0

:: 1. ファイルのシンボリックリンク作成
echo Creating symbolic links...
call :CreateFileLink "%USERPROFILE%\.ideavimrc" "%DOTFILES%.ideavimrc"
call :CreateFileLink "%USERPROFILE%\.gitconfig" "%DOTFILES%.gitconfig"

:: --- .gitconfig.local (credential.helper等のOS別設定) は example からコピー ---
call :CopyWithPrompt "%DOTFILES%.gitconfig.local.example" "%USERPROFILE%\.gitconfig.local"

:: 2. ディレクトリのシンボリックリンク作成
call :CreateDirLink "%USERPROFILE%\.ssh" "%DOTFILES%..\.ssh"

:: --- 重要: .wslconfig はリンクではなく「コピー」を行う ---
call :CopyWithPrompt "%DOTFILES%.wslconfig" "%USERPROFILE%\.wslconfig"

:: --- 重要: Windows Terminal settings.json は「コピー」で配置する ---
:: (シンボリックリンクだと保存時にリンクが壊れるため)
set WT_DIR=%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState
if exist "%WT_DIR%" (
    call :CopyWithPrompt "%DOTFILES%.config\windows-terminal\settings.json" "%WT_DIR%\settings.json"
) else (
    echo Windows Terminal not found. Skipping settings.json.
)

echo Setup Completed! Please run "wsl --shutdown" in PowerShell to apply changes.

pause
exit /b

:: --- 関数: ファイルのシンボリックリンク作成 (既存時は上書き確認) ---
:CreateFileLink
set "LINK_PATH=%~1"
set "TARGET_PATH=%~2"

if exist "%LINK_PATH%" (
    set /p "ANSWER=%LINK_PATH% already exists. Overwrite? (y/N): "
    if /i "!ANSWER:~0,1!"=="y" (
        del "%LINK_PATH%"
    ) else (
        echo Skipped: %LINK_PATH%
        goto :eof
    )
)
echo Creating link for %LINK_PATH%...
mklink "%LINK_PATH%" "%TARGET_PATH%"
goto :eof

:: --- 関数: ディレクトリのシンボリックリンク作成 (既存時は上書き確認) ---
:CreateDirLink
set "LINK_PATH=%~1"
set "TARGET_PATH=%~2"

if exist "%LINK_PATH%" (
    set /p "ANSWER=%LINK_PATH% already exists. Overwrite? (y/N): "
    if /i "!ANSWER:~0,1!"=="y" (
        rmdir /s /q "%LINK_PATH%"
    ) else (
        echo Skipped: %LINK_PATH%
        goto :eof
    )
)
echo Creating link for %LINK_PATH%...
mklink /D "%LINK_PATH%" "%TARGET_PATH%"
goto :eof

:: --- 関数: ファイルのコピー配置 (既存時は上書き確認、.bakへバックアップ) ---
:CopyWithPrompt
set "SRC_PATH=%~1"
set "DST_PATH=%~2"

if exist "%DST_PATH%" (
    set /p "ANSWER=%DST_PATH% already exists. Overwrite? (y/N): "
    if /i "!ANSWER:~0,1!"=="y" (
        echo Backing up existing file to %DST_PATH%.bak...
        copy /Y "%DST_PATH%" "%DST_PATH%.bak" >nul
    ) else (
        echo Skipped: %DST_PATH%
        goto :eof
    )
)
echo Copying to %DST_PATH%...
copy /Y "%SRC_PATH%" "%DST_PATH%"
goto :eof
