@echo off
setlocal enabledelayedexpansion
set DOTFILES=%~dp0

echo 既存のシンボリックリンクを削除しています...

:: 1. ファイルのリンク削除 (del コマンドを使用)
if exist "%USERPROFILE%\.ideavimrc" (
    echo Deleting file link: .ideavimrc
    del "%USERPROFILE%\.ideavimrc"
)

if exist "%USERPROFILE%\.wslconfig" (
    echo Deleting file link: .wslconfig
    del "%USERPROFILE%\.wslconfig"
)

set WT_SETTINGS=%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json
if exist "%WT_SETTINGS%" (
    echo Deleting file: Windows Terminal settings.json
    del "%WT_SETTINGS%"
)

:: 2. ディレクトリのリンク削除 (rmdir コマンドを使用)
call :RemoveLink "%USERPROFILE%\.ssh"

echo.
echo Done!
pause
exit /b

:: --- 関数: ディレクトリのシンボリックリンク削除 ---
:RemoveLink
set "LINK_PATH=%~1"

if exist "%LINK_PATH%" (
    :: ディレクトリか、あるいはディレクトリのシンボリックリンクかを確認
    echo Removing directory link: %LINK_PATH%
    rmdir "%LINK_PATH%"
) else (
    echo %LINK_PATH% does not exist. Skipping.
)
goto :eof
