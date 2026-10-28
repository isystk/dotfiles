<#
.SYNOPSIS
  マウスの戻る/進むボタン(XButton1/XButton2)を、Windows Terminal前面時のみ Ctrl+Left / Ctrl+Right に置き換える常駐スクリプト。

.DESCRIPTION
  WSL上のNeovimでは <C-Left> / <C-Right> をジャンプリストの戻る/進む(<C-o> / <C-i>)に
  割り当てているため、マウスの戻る/進むボタンで表示ファイルを行き来できるようにする。
  低レベルマウスフック(WH_MOUSE_LL)でXButtonを検知し、フォアグラウンドが
  Windows Terminalのときだけ元のクリックを捨ててキー入力を送る。
  ブラウザ等の他アプリでは何もせず、本来の戻る/進む動作のまま。

.NOTES
  実行ファイル(exe)ではなくPowerShellスクリプトとして配布することで、
  セキュリティソフトによる未署名exe検知を避ける。
  Windows Terminalを管理者権限で起動している場合、UIPIによりキー送信がブロックされ動作しない。

  スタートアップ登録は mouse-xbutton-watcher-launcher.vbs を対象にすること
  (windows/setup.bat が shell:startup へショートカットを作成する)。

  本ファイルはUTF-8 with BOMで保存すること。BOM無しUTF-8の場合、
  Windows PowerShell 5.1がシステムロケール(日本語環境ではShift-JIS)として
  誤読し、日本語コメントの文字化けによりパースエラーになることがある。
#>

# 対象プロセス名(拡張子なし)。他のターミナルでも使う場合はここへ追加する。
$TargetProcessNames = @("WindowsTerminal")

# 二重起動防止
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, "Local\mouse-xbutton-watcher", [ref]$createdNew)
if (-not $createdNew) { exit }

Add-Type -ReferencedAssemblies System.Windows.Forms @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class XButtonHook {
    private delegate IntPtr LowLevelMouseProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int x, y; }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSLLHOOKSTRUCT {
        public POINT pt;
        public uint mouseData;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelMouseProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    private const int WH_MOUSE_LL = 14;
    private const int WM_XBUTTONDOWN = 0x020B;
    private const int WM_XBUTTONUP = 0x020C;
    private const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const byte VK_CONTROL = 0x11;
    private const byte VK_LEFT = 0x25;
    private const byte VK_RIGHT = 0x27;

    private static IntPtr hookId = IntPtr.Zero;
    // GC回収を防ぐため静的フィールドで保持する
    private static LowLevelMouseProc proc = HookCallback;
    private static HashSet<string> targets = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

    private static bool IsTargetForeground() {
        IntPtr hwnd = GetForegroundWindow();
        if (hwnd == IntPtr.Zero) { return false; }
        uint pid;
        GetWindowThreadProcessId(hwnd, out pid);
        try {
            using (Process p = Process.GetProcessById((int)pid)) {
                return targets.Contains(p.ProcessName);
            }
        } catch {
            return false;
        }
    }

    private static void SendCtrlArrow(byte arrowVk) {
        keybd_event(VK_CONTROL, 0, 0, UIntPtr.Zero);
        keybd_event(arrowVk, 0, KEYEVENTF_EXTENDEDKEY, UIntPtr.Zero);
        keybd_event(arrowVk, 0, KEYEVENTF_EXTENDEDKEY | KEYEVENTF_KEYUP, UIntPtr.Zero);
        keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0) {
            int msg = wParam.ToInt32();
            if (msg == WM_XBUTTONDOWN || msg == WM_XBUTTONUP) {
                if (IsTargetForeground()) {
                    MSLLHOOKSTRUCT info = (MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(MSLLHOOKSTRUCT));
                    uint button = (info.mouseData >> 16) & 0xFFFF; // 1=XButton1(戻る), 2=XButton2(進む)
                    if (msg == WM_XBUTTONDOWN) {
                        if (button == 1) { SendCtrlArrow(VK_LEFT); }
                        else if (button == 2) { SendCtrlArrow(VK_RIGHT); }
                    }
                    // DOWN/UPとも握りつぶし、Windows Terminalへ元のクリックを渡さない
                    return (IntPtr)1;
                }
            }
        }
        return CallNextHookEx(hookId, nCode, wParam, lParam);
    }

    public static void Run(string[] processNames) {
        foreach (string n in processNames) { targets.Add(n); }
        using (Process cur = Process.GetCurrentProcess())
        using (ProcessModule mod = cur.MainModule) {
            hookId = SetWindowsHookEx(WH_MOUSE_LL, proc, GetModuleHandle(mod.ModuleName), 0);
        }
        if (hookId == IntPtr.Zero) {
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
        try {
            // 低レベルフックはメッセージループを回すスレッドで受ける必要がある
            Application.Run();
        } finally {
            UnhookWindowsHookEx(hookId);
        }
    }
}
"@

[XButtonHook]::Run($TargetProcessNames)
