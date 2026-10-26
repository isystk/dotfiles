@echo off
setlocal enabledelayedexpansion
set DOTFILES=%~dp0

echo 既存のシンボリックリンクを削除しています...

:: 1. ファイルのリンク削除 (シンボリックリンクの場合のみ削除)
call :RemoveFileLink "%USERPROFILE%\.ideavimrc"

:: .wslconfig / Windows Terminal settings.json は setup.bat が「コピー」配置したもの。
:: 実設定を失わないよう削除せず、手動での扱いを案内する。
echo Note: .wslconfig and Windows Terminal settings.json are copies and were NOT deleted.
echo       Restore from *.bak.* manually if needed.

:: 2. ディレクトリのリンク削除 (リンクの場合のみ)
call :RemoveLink "%USERPROFILE%\.ssh"


:: 3. スタートアップのショートカット削除
call :RemoveStartupShortcut "mouse-xbutton-watcher"

echo.
echo Done!
pause
exit /b

:: --- 関数: シンボリックリンク判定 (dir /AL で当該エントリがリンクか確認) ---
:IsLink
set "IL_PARENT=%~dp1"
set "IL_NAME=%~nx1"
dir /AL /B "%IL_PARENT%" 2>nul | findstr /X /I /C:"%IL_NAME%" >nul
exit /b %errorlevel%

:: --- 関数: ファイルのシンボリックリンク削除 (実ファイルは削除しない) ---
:RemoveFileLink
set "LINK_PATH=%~1"
call :IsLink "%LINK_PATH%"
if !errorlevel! equ 0 (
    echo Deleting file link: %LINK_PATH%
    del "%LINK_PATH%"
) else if exist "%LINK_PATH%" (
    echo %LINK_PATH% is a real file, not a link. Skipping.
) else (
    echo %LINK_PATH% does not exist. Skipping.
)
goto :eof

:: --- 関数: ディレクトリのシンボリックリンク削除 (実ディレクトリは削除しない) ---
:RemoveLink
set "LINK_PATH=%~1"
call :IsLink "%LINK_PATH%"
if !errorlevel! equ 0 (
    echo Removing directory link: %LINK_PATH%
    rmdir "%LINK_PATH%"
) else if exist "%LINK_PATH%" (
    echo %LINK_PATH% is a real directory, not a link. Skipping.
) else (
    echo %LINK_PATH% does not exist. Skipping.
)
goto :eof

:: --- 関数: スタートアップのショートカット削除 ---
:RemoveStartupShortcut
set "SC_PATH=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\%~1.lnk"
if exist "%SC_PATH%" (
    echo Deleting startup shortcut: %SC_PATH%
    del "%SC_PATH%"
) else (
    echo %SC_PATH% does not exist. Skipping.
)
goto :eof
