@echo off
setlocal enabledelayedexpansion
set DOTFILES=%~dp0

:: 管理者権限がないと mklink が失敗するため事前確認 (開発者モード有効なら管理者でなくても可)
net session >nul 2>&1
if errorlevel 1 (
    echo This script requires Administrator privileges for mklink. Run as Administrator.
    pause
    exit /b 1
)

:: 1. ファイルのシンボリックリンク作成
echo Creating symbolic links...
call :CreateFileLink "%USERPROFILE%\.ideavimrc" "%DOTFILES%..\.ideavimrc"

:: 2. ディレクトリのシンボリックリンク作成
call :CreateDirLink "%USERPROFILE%\.ssh" "%DOTFILES%..\..\.ssh"

:: --- 重要: .wslconfig はリンクではなく「コピー」を行う ---
call :CopyWithBackup "%DOTFILES%.wslconfig" "%USERPROFILE%\.wslconfig"

:: --- 重要: Windows Terminal settings.json は「コピー」で配置する ---
:: (シンボリックリンクだと保存時にリンクが壊れるため)
set WT_DIR=%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState
if exist "%WT_DIR%" (
    call :CopyWithBackup "%DOTFILES%windows-terminal\settings.json" "%WT_DIR%\settings.json"
) else (
    echo Windows Terminal not found. Skipping settings.json.
)

:: --- マウスの戻る/進むボタン -> Ctrl+Left/Right 変換ウォッチャーをスタートアップへ登録 ---
:: (launcher.vbs へのショートカットを shell:startup に作成。既存は .bak へ退避)
call :CreateStartupShortcut "mouse-xbutton-watcher" "%DOTFILES%tools\mouse-xbutton-watcher-launcher.vbs"

echo Setup Completed! Please run "wsl --shutdown" in PowerShell to apply changes.

pause
exit /b

:: --- 関数: シンボリックリンク判定 (dir /AL で当該エントリがリンクか確認) ---
:IsLink
set "IL_PARENT=%~dp1"
set "IL_NAME=%~nx1"
dir /AL /B "%IL_PARENT%" 2>nul | findstr /X /I /C:"%IL_NAME%" >nul
exit /b %errorlevel%

:: --- 関数: 既存のファイル/ディレクトリ/リンクを .bak.<日時> へ退避 (削除しない) ---
:Backup
set "BK_PATH=%~1"
for %%I in ("%BK_PATH%") do set "BK_NAME=%%~nxI"
for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format yyyyMMddHHmmss"`) do set "BK_STAMP=%%T"
echo Backing up %BK_PATH% to !BK_NAME!.bak.!BK_STAMP!
ren "%BK_PATH%" "!BK_NAME!.bak.!BK_STAMP!"
goto :eof

:: --- 関数: ファイルのシンボリックリンク作成 (既存は確認なしで退避してから作成) ---
:CreateFileLink
set "LINK_PATH=%~1"
set "TARGET_PATH=%~2"

call :IsLink "%LINK_PATH%"
if !errorlevel! equ 0 (
    echo Link already exists: %LINK_PATH%
    goto :eof
)
if exist "%LINK_PATH%" call :Backup "%LINK_PATH%"
echo Creating link for %LINK_PATH%...
mklink "%LINK_PATH%" "%TARGET_PATH%"
goto :eof

:: --- 関数: ディレクトリのシンボリックリンク作成 (既存は確認なしで退避してから作成) ---
:CreateDirLink
set "LINK_PATH=%~1"
set "TARGET_PATH=%~2"

call :IsLink "%LINK_PATH%"
if !errorlevel! equ 0 (
    echo Link already exists: %LINK_PATH%
    goto :eof
)
if exist "%LINK_PATH%" call :Backup "%LINK_PATH%"
echo Creating link for %LINK_PATH%...
mklink /D "%LINK_PATH%" "%TARGET_PATH%"
goto :eof

:: --- 関数: ファイルのコピー配置 (既存は確認なしで .bak.<日時> へ退避してから上書き) ---
:CopyWithBackup
set "SRC_PATH=%~1"
set "DST_PATH=%~2"

if exist "%DST_PATH%" call :Backup "%DST_PATH%"
echo Copying to %DST_PATH%...
copy /Y "%SRC_PATH%" "%DST_PATH%"
goto :eof

:: --- 関数: スタートアップフォルダへのショートカット作成 (既存は .bak.<日時> へ退避) ---
:CreateStartupShortcut
set "SC_NAME=%~1"
set "SC_TARGET=%~f2"
set "SC_PATH=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\%SC_NAME%.lnk"

if not exist "%SC_TARGET%" (
    echo Startup target not found: %SC_TARGET%. Skipping.
    goto :eof
)
if exist "%SC_PATH%" call :Backup "%SC_PATH%"
echo Creating startup shortcut %SC_PATH%...
powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut($env:SC_PATH); $s.TargetPath=$env:SC_TARGET; $s.WorkingDirectory=Split-Path $env:SC_TARGET; $s.Save()"
goto :eof
