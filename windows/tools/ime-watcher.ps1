<#
.SYNOPSIS
  Neovim(WSL)側からのトリガーファイル更新を検知し、フォアグラウンドウィンドウのIMEをオフにする常駐スクリプト。

.DESCRIPTION
  WSL上のNeovimはパネル移動(WinLeave)等でexeを都度起動する方式だと
  GetForegroundWindow()の対象がずれてIME切替が効かない問題があるため、
  常時起動の本スクリプト側でフォーカスウィンドウを取得しIMEを操作する。
  WSL側は単純にトリガーファイルを書き換えるだけで良く、Windows側で
  プロセスを都度起動する必要がない。

.NOTES
  実行ファイル(exe)ではなくPowerShellスクリプトとして配布することで、
  セキュリティソフトによる未署名exe検知を避ける。

  スタートアップ登録例 (shell:startup フォルダにショートカットを作成):
    リンク先: powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\path\to\ime-watcher.ps1"

  本ファイルはUTF-8 with BOMで保存すること。BOM無しUTF-8の場合、
  Windows PowerShell 5.1がシステムロケール(日本語環境ではShift-JIS)として
  誤読し、日本語コメントの文字化けによりパースエラーになることがある。
#>

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class ImeHelper {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left, Top, Right, Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct GUITHREADINFO {
        public uint cbSize;
        public uint flags;
        public IntPtr hwndActive;
        public IntPtr hwndFocus;
        public IntPtr hwndCapture;
        public IntPtr hwndMenuOwner;
        public IntPtr hwndMoveSize;
        public IntPtr hwndCaret;
        public RECT rcCaret;
    }

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool GetGUIThreadInfo(uint idThread, ref GUITHREADINFO lpgui);

    [DllImport("imm32.dll")]
    public static extern IntPtr ImmGetDefaultIMEWnd(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    private const uint WM_IME_CONTROL = 0x0283;
    private const uint IMC_SETOPENSTATUS = 0x006;

    // GetForegroundWindow() alone returns the top-level window, which can differ from the
    // control that actually owns keyboard focus inside composite apps like Windows Terminal.
    // Prefer GetGUIThreadInfo's hwndFocus when available (same approach as vimmer-ahk).
    public static void SetImeOff() {
        IntPtr hwnd = GetForegroundWindow();
        GUITHREADINFO gti = new GUITHREADINFO();
        gti.cbSize = (uint)Marshal.SizeOf(gti);
        if (GetGUIThreadInfo(0, ref gti) && gti.hwndFocus != IntPtr.Zero) {
            hwnd = gti.hwndFocus;
        }
        if (hwnd == IntPtr.Zero) { return; }
        IntPtr imeWnd = ImmGetDefaultIMEWnd(hwnd);
        if (imeWnd == IntPtr.Zero) { return; }
        SendMessage(imeWnd, WM_IME_CONTROL, (IntPtr)IMC_SETOPENSTATUS, IntPtr.Zero);
    }
}
"@

# WSL側($HOME直下)のトリガーファイルをUNCパスで監視する。
# ディストリビューション名・Linuxユーザー名(root/一般ユーザーどちらでも可)は
# 起動時に wsl.exe 経由で自動取得するため、環境が変わっても書き換え不要。
# wsl.exeの出力はUTF-16LEでヌルバイトが混入することがあるため、
# 対話シェルと異なり-File実行時は文字列処理が壊れる。ヌルバイトを除去してから使う。
function Get-WslOutput([string]$Command) {
    $raw = (wsl.exe -- sh -c $Command) -join ''
    return ($raw -replace "`0", '').Trim()
}
$wslDistro = Get-WslOutput 'echo $WSL_DISTRO_NAME'
$wslHome = (Get-WslOutput 'echo $HOME') -replace '/', '\'
$TriggerPath = "\\wsl.localhost\$wslDistro$wslHome\.nvim-ime-off-trigger"
$PollIntervalMs = 100

$lastWriteTime = [DateTime]::MinValue

while ($true) {
    try {
        if (Test-Path -LiteralPath $TriggerPath) {
            $currentWriteTime = (Get-Item -LiteralPath $TriggerPath -ErrorAction Stop).LastWriteTime
            if ($currentWriteTime -ne $lastWriteTime) {
                $lastWriteTime = $currentWriteTime
                [ImeHelper]::SetImeOff()
            }
        }
    } catch {
        # WSL未起動時などUNCパスへアクセスできない瞬間は無視して次のポーリングへ
    }
    Start-Sleep -Milliseconds $PollIntervalMs
}
