<#
.SYNOPSIS
  CapsLockキーをCtrlキーとして機能させる設定をトグルするスクリプト。

.DESCRIPTION
  レジストリのScancode Map(HKCU\Keyboard Layout)を書き換え、
  CapsLock -> 左Ctrlのキー入れ替えを行う。
  実行済みかどうかを自動判定し、
    - 未適用なら「変更する」確認をとって適用
    - 適用済みなら「元に戻す」確認をとって解除
  を行う。設定の反映にはサインアウトまたは再起動が必要。

.NOTES
  本ファイルはUTF-8 with BOMで保存すること。BOM無しUTF-8の場合、
  Windows PowerShell 5.1がシステムロケール(日本語環境ではShift-JIS)として
  誤読し、日本語コメントの文字化けによりパースエラーになることがある。

  Scancode MapはHKCU(ユーザー単位)とHKLM(システム全体)のどちらにも
  設定可能。両方存在する場合はHKLM側が優先される。
  本スクリプトは既存設定をHKLM→HKCUの順で検出し、見つかった方を解除する。
  未設定の場合はHKLM(システム全体・管理者権限必須)に新規適用する。

  実行例:
    powershell.exe -ExecutionPolicy Bypass -File "C:\path\to\toggle-capslock-ctrl.ps1"
#>

$HklmPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout"
$HkcuPath = "HKCU:\Keyboard Layout"
$RegName = "Scancode Map"

# CapsLock(3A) -> 左Ctrl(1D) への入れ替えマップ
# ヘッダ8byte(0) + マッピング数(2、うち1件+終端) + マッピング本体(1D00 3A00) + 終端(0000 0000)
$CapsToCtrlMap = [byte[]](
    0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,
    0x02,0x00,0x00,0x00,
    0x1D,0x00,0x3A,0x00,
    0x00,0x00,0x00,0x00
)

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$hklmExisting = Get-ItemProperty -Path $HklmPath -Name $RegName -ErrorAction SilentlyContinue
$hkcuExisting = Get-ItemProperty -Path $HkcuPath -Name $RegName -ErrorAction SilentlyContinue

if ($hklmExisting -or $hkcuExisting) {
    $target = if ($hklmExisting) { "HKLM(システム全体)" } else { "HKCU(ユーザー単位)" }
    Write-Host "現在、CapsLockはCtrlキーとして動作する設定になっています。（設定場所: $target）"
    $answer = Read-Host "元に戻しますか？(CapsLockキーを本来の動作に戻す) [y/N]"
    if ($answer -eq "y" -or $answer -eq "Y") {
        if ($hklmExisting) {
            if (-not (Test-IsAdmin)) {
                Write-Host "エラー: HKLM側の設定解除には管理者権限が必要です。PowerShellを「管理者として実行」で開き直してください。"
                exit 1
            }
            Remove-ItemProperty -Path $HklmPath -Name $RegName -ErrorAction Stop
        }
        if ($hkcuExisting) {
            Remove-ItemProperty -Path $HkcuPath -Name $RegName -ErrorAction Stop
        }
        Write-Host "設定を解除しました。反映にはサインアウトまたは再起動が必要です。"
    } else {
        Write-Host "キャンセルしました。設定は変更していません。"
    }
} else {
    Write-Host "現在、CapsLockキーは本来の動作のままです。"
    $answer = Read-Host "CapsLockキーをCtrlキーに変更しますか？(システム全体に適用/要管理者権限) [y/N]"
    if ($answer -eq "y" -or $answer -eq "Y") {
        if (-not (Test-IsAdmin)) {
            Write-Host "エラー: システム全体への適用には管理者権限が必要です。PowerShellを「管理者として実行」で開き直してください。"
            exit 1
        }
        New-ItemProperty -Path $HklmPath -Name $RegName -PropertyType Binary -Value $CapsToCtrlMap -Force | Out-Null
        Write-Host "設定を適用しました。反映にはサインアウトまたは再起動が必要です。"
    } else {
        Write-Host "キャンセルしました。設定は変更していません。"
    }
}
