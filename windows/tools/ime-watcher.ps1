<#
.SYNOPSIS
  Neovim(WSL)側からのNamed Pipe通知を受け、フォアグラウンドウィンドウのIMEをオフにする常駐スクリプト。

.DESCRIPTION
  WSL上のNeovimはパネル移動(WinLeave)等でIME操作exeを都度起動する方式だと
  GetForegroundWindow()の対象がずれてIME切替が効かない問題があるため、
  常時起動の本スクリプト側でフォーカスウィンドウを取得しIMEを操作する。
  WSL側はNamed Pipe(nvim-ime-off)へ1行書き込むだけで通知でき、
  実際のIME操作を行うexe起動は不要。

  \\wsl.localhost経由のファイルポーリングは高頻度なUNC越しアクセスが
  WSL2の9pファイルシステム層に負荷をかけWSLイメージ破損を招くため、
  push型のNamed Pipe通知方式にする。

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

# WSL(Neovim)側からのNamed Pipe接続を待ち受け、1行=1通知としてIMEをオフにする。
# パイプ名はローカル固定のため、WSLディストロ名の解決(wsl.exe呼び出し)も不要。
# Neovim側は起動時に接続したパイプを張りっぱなしにするため、1接続中に複数行
# 届く前提でストリームが切れるまで読み続ける(切断されたら次の接続を待つ)。
$PipeName = "nvim-ime-off"

while ($true) {
    $server = $null
    try {
        $server = New-Object System.IO.Pipes.NamedPipeServerStream(
            $PipeName,
            [System.IO.Pipes.PipeDirection]::In
        )
        $server.WaitForConnection()
        $reader = New-Object System.IO.StreamReader($server)
        while ($server.IsConnected) {
            $line = $reader.ReadLine()
            if ($null -eq $line) { break }
            [ImeHelper]::SetImeOff()
        }
    } catch {
        # クライアント切断タイミング等の一時的な例外は無視し、次の接続待ちへ
        Start-Sleep -Milliseconds 100
    } finally {
        if ($server) { $server.Dispose() }
    }
}
