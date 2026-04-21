#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configura il Kiosk Mode v3.0 sulla macchina.
    Eseguire come Amministratore.

.DESCRIPTION
    1. Crea utente locale kiosk (opzionale)
    2. Blocca hotkey/TaskManager in HKLM (da admin, nessun errore permessi)
    3. Configura shell = Start-Kiosk.vbs (launcher invisibile)
    4. Configura autologon (opzionale)

.EXAMPLE
    .\Setup-Kiosk.ps1                                       # Setup con utente corrente
    .\Setup-Kiosk.ps1 -KioskUser "kiosk" -CreateUser        # Crea utente + setup
    .\Setup-Kiosk.ps1 -KioskUser "kiosk" -SetAutologon      # Setup + autologon
    .\Setup-Kiosk.ps1 -Undo                                 # Ripristino completo
#>

param(
    [string]$KioskUser   = $env:USERNAME,
    [string]$KioskDomain = "",
    [switch]$CreateUser,
    [switch]$SetAutologon,
    [switch]$Undo
)

$ErrorActionPreference = "Stop"

$KioskFolder    = "C:\Kiosk"
$LogFolder      = "$KioskFolder\Logs"
$WinlogonPath   = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

# La shell ora punta al VBS invisibile (nessuna finestra CMD/PS visibile)
$ShellValue     = "wscript.exe ""C:\Kiosk\Start-Kiosk.vbs"""

$RequiredFiles  = @(
    "$KioskFolder\Start-Kiosk.vbs"
    "$KioskFolder\Start-Kiosk.ps1"
)

# ============================================================
#  UNDO
# ============================================================

if ($Undo) {
    Write-Host ""
    Write-Host "=== RIPRISTINO KIOSK MODE ===" -ForegroundColor Cyan
    Write-Host ""

    # Shell
    $backup = (Get-ItemProperty -Path $WinlogonPath -Name "Shell_Backup" -ErrorAction SilentlyContinue).Shell_Backup
    $restoreShell = if ($backup) { $backup } else { "explorer.exe" }
    Set-ItemProperty -Path $WinlogonPath -Name "Shell" -Value $restoreShell
    Remove-ItemProperty -Path $WinlogonPath -Name "Shell_Backup" -ErrorAction SilentlyContinue
    Write-Host "[OK] Shell ripristinata: $restoreShell" -ForegroundColor Green

    # Autologon
    $answer = Read-Host "Rimuovere autologon? (S/N)"
    if ($answer -match "^[Ss]$") {
        Set-ItemProperty -Path $WinlogonPath -Name "AutoAdminLogon" -Value "0"
        Remove-ItemProperty -Path $WinlogonPath -Name "DefaultPassword" -ErrorAction SilentlyContinue
        Write-Host "[OK] Autologon rimosso" -ForegroundColor Green
    }

    # Hotkey HKLM
    $expPolicy = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    $sysPolicy = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    Remove-ItemProperty -Path $sysPolicy -Name "DisableTaskMgr" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $expPolicy -Name "NoWinKeys"      -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $expPolicy -Name "NoRun"          -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $expPolicy -Name "DisableChangePassword" -ErrorAction SilentlyContinue
    Write-Host "[OK] Hotkey sbloccati" -ForegroundColor Green

    Write-Host ""
    Write-Host "[FATTO] Riavviare il PC." -ForegroundColor Green
    exit 0
}

# ============================================================
#  SETUP
# ============================================================

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "       SETUP KIOSK MODE v3.0" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Utente  : $KioskUser"
Write-Host "  Shell   : $ShellValue"
Write-Host "  Cartella: $KioskFolder"
Write-Host ""

$stepNum = 0

# -------------------------------------------------------
# STEP: Crea utente locale (opzionale)
# -------------------------------------------------------
$stepNum++
if ($CreateUser) {
    Write-Host "[$stepNum] Creazione utente locale '$KioskUser'..." -ForegroundColor Yellow

    $existingUser = Get-LocalUser -Name $KioskUser -ErrorAction SilentlyContinue
    if ($existingUser) {
        Write-Host "    Utente '$KioskUser' esiste gia'" -ForegroundColor DarkGray
    }
    else {
        $userPwd = Read-Host "    Password per '$KioskUser'" -AsSecureString
        New-LocalUser -Name $KioskUser `
                      -Password $userPwd `
                      -FullName "Kiosk User" `
                      -Description "Account kiosk - shell personalizzata" `
                      -PasswordNeverExpires `
                      -UserMayNotChangePassword

        # Aggiungi solo al gruppo Users (NON Administrators)
        Add-LocalGroupMember -Group "Users" -Member $KioskUser -ErrorAction SilentlyContinue
        Write-Host "    [OK] Utente creato (gruppo: Users, NO admin)" -ForegroundColor Green
    }
}
else {
    Write-Host "[$stepNum] Creazione utente: saltata (usa -CreateUser)" -ForegroundColor DarkGray
}

# -------------------------------------------------------
# STEP: Cartelle
# -------------------------------------------------------
$stepNum++
Write-Host ""
Write-Host "[$stepNum] Creazione cartelle..." -ForegroundColor Yellow
@($KioskFolder, $LogFolder) | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -Path $_ -ItemType Directory -Force | Out-Null }
    Write-Host "    $_ [OK]" -ForegroundColor DarkGray
}

# -------------------------------------------------------
# STEP: Verifica file
# -------------------------------------------------------
$stepNum++
Write-Host ""
Write-Host "[$stepNum] Verifica file..." -ForegroundColor Yellow
$missing = @()
foreach ($f in $RequiredFiles) {
    if (Test-Path $f) {
        Write-Host "    $f [OK]" -ForegroundColor DarkGray
    }
    else {
        Write-Host "    $f [MANCANTE]" -ForegroundColor Red
        $missing += $f
    }
}
if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "    ATTENZIONE: copiare i file mancanti prima di riavviare!" -ForegroundColor Red
    $go = Read-Host "    Continuare comunque? (S/N)"
    if ($go -notmatch "^[Ss]$") { exit 0 }
}

# -------------------------------------------------------
# STEP: Blocco hotkey in HKLM (da admin, nessun errore permessi)
# -------------------------------------------------------
$stepNum++
Write-Host ""
Write-Host "[$stepNum] Blocco hotkey (HKLM, valido per tutti gli utenti)..." -ForegroundColor Yellow

# TaskManager
$sysPolicy = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
if (-not (Test-Path $sysPolicy)) { New-Item -Path $sysPolicy -Force | Out-Null }
Set-ItemProperty -Path $sysPolicy -Name "DisableTaskMgr" -Value 1 -Type DWord
Write-Host "    DisableTaskMgr = 1 [OK]" -ForegroundColor DarkGray

# Win keys, Run dialog, Change Password
$expPolicy = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
if (-not (Test-Path $expPolicy)) { New-Item -Path $expPolicy -Force | Out-Null }
Set-ItemProperty -Path $expPolicy -Name "NoWinKeys" -Value 1 -Type DWord
Set-ItemProperty -Path $expPolicy -Name "NoRun"     -Value 1 -Type DWord
Write-Host "    NoWinKeys = 1 [OK]" -ForegroundColor DarkGray
Write-Host "    NoRun = 1 [OK]" -ForegroundColor DarkGray

Write-Host "    [OK] Hotkey bloccati" -ForegroundColor Green

# -------------------------------------------------------
# STEP: Shell replacement
# -------------------------------------------------------
$stepNum++
Write-Host ""
Write-Host "[$stepNum] Configurazione shell..." -ForegroundColor Yellow

$currentShell = (Get-ItemProperty -Path $WinlogonPath -Name "Shell" -ErrorAction SilentlyContinue).Shell
if ($currentShell -and $currentShell -ne $ShellValue) {
    Set-ItemProperty -Path $WinlogonPath -Name "Shell_Backup" -Value $currentShell
    Write-Host "    Backup: $currentShell" -ForegroundColor DarkGray
}

Set-ItemProperty -Path $WinlogonPath -Name "Shell" -Value $ShellValue

$verify = (Get-ItemProperty -Path $WinlogonPath -Name "Shell").Shell
if ($verify -eq $ShellValue) {
    Write-Host "    Shell = $ShellValue [OK]" -ForegroundColor Green
}
else {
    Write-Host "    ERRORE verifica! Letto: $verify" -ForegroundColor Red
}

# -------------------------------------------------------
# STEP: Autologon
# -------------------------------------------------------
$stepNum++
Write-Host ""
if ($SetAutologon) {
    Write-Host "[$stepNum] Configurazione autologon..." -ForegroundColor Yellow

    $secPwd = Read-Host "    Password per '$KioskUser'" -AsSecureString

    Set-ItemProperty -Path $WinlogonPath -Name "AutoAdminLogon"  -Value "1"
    Set-ItemProperty -Path $WinlogonPath -Name "DefaultUserName" -Value $KioskUser

    if ($KioskDomain) {
        Set-ItemProperty -Path $WinlogonPath -Name "DefaultDomainName" -Value $KioskDomain
    }

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPwd)
    $plainPwd = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    Set-ItemProperty -Path $WinlogonPath -Name "DefaultPassword" -Value $plainPwd
    $plainPwd = $null; [System.GC]::Collect()

    Write-Host "    Autologon per '$KioskUser' [OK]" -ForegroundColor Green
}
else {
    Write-Host "[$stepNum] Autologon: saltato (usa -SetAutologon)" -ForegroundColor DarkGray
}

# -------------------------------------------------------
# RIEPILOGO
# -------------------------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "       SETUP COMPLETATO" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  File necessari in C:\Kiosk\:" -ForegroundColor White
Write-Host "    Start-Kiosk.vbs   (launcher invisibile)"
Write-Host "    Start-Kiosk.ps1   (logica kiosk)"
Write-Host ""
Write-Host "  Catena di avvio:" -ForegroundColor White
Write-Host "    Boot -> Autologon -> wscript Start-Kiosk.vbs (invisibile)"
Write-Host "                      -> PowerShell (nascosto)"
Write-Host "                      -> App a tutto schermo"
Write-Host "                      -> Chiusura app -> Shutdown"
Write-Host ""
Write-Host "  Per RIPRISTINARE: .\Setup-Kiosk.ps1 -Undo" -ForegroundColor Yellow
Write-Host ""
Write-Host "  EMERGENZA:" -ForegroundColor Red
Write-Host "    Safe Mode -> regedit -> Winlogon -> Shell = explorer.exe"
Write-Host ""
