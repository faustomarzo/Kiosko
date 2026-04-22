#Requires -Version 5.1
<#
.SYNOPSIS
    Kiosk Shell Wrapper v3.0 - Avvia un'applicazione a tutto schermo
    e spegne la macchina alla chiusura.

.DESCRIPTION
    Chiamato dal launcher VBS (invisibile). Questo script:
    1. Avvia l'applicazione configurata (fullscreen)
    2. Monitora il processo
    3. Spegne il PC quando l'utente chiude l'app

.NOTES
    Autore:  Fausto - RAI ICT
    Versione: 3.0
    Data:    2026-04-14

    CONFIGURAZIONE:
    - Per TEST: $AppProfile = "TEST" (VLC)
    - Per PRODUZIONE: $AppProfile = "PROD" (titan.exe)
#>

# ============================================================
#  CONFIGURAZIONE
# ============================================================

$AppProfile = "TEST"   # <-- Cambiare in "PROD" per titan.exe

$AppProfiles = @{
    TEST = @{
        Name     = "VLC Media Player"
        Path     = "C:\Program Files\VideoLAN\VLC\vlc.exe"
        Args     = "--fullscreen"    # VLC: avvia a schermo intero
        Process  = "vlc"
    }
    PROD = @{
        Name     = "Titan"
        Path     = "C:\Program Files\Titan\titan.exe"
        Args     = ""               # <-- Adatta se titan ha flag fullscreen
        Process  = "titan"
    }
}

$LogFolder     = "C:\Kiosk\Logs"
$LogFile       = Join-Path $LogFolder "kiosk_$(Get-Date -Format 'yyyyMMdd').log"
$ShutdownDelay = 5
$MaxRetries    = 3

# ============================================================
#  FUNZIONI
# ============================================================

function Write-KioskLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"

    if (-not (Test-Path $LogFolder)) {
        New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
    }

    $entry | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

function Start-KioskApp {
    param([hashtable]$Profile)

    $attempt = 0

    while ($attempt -lt $MaxRetries) {
        $attempt++
        Write-KioskLog "Tentativo avvio $($Profile.Name) ($attempt/$MaxRetries)..."

        if (-not (Test-Path $Profile.Path)) {
            Write-KioskLog "ERRORE: File non trovato: $($Profile.Path)" "ERROR"
            Start-Sleep -Seconds 3
            continue
        }

        try {
            $splat = @{
                FilePath    = $Profile.Path
                PassThru    = $true
                WindowStyle = "Maximized"    # Finestra massimizzata come fallback
            }
            if ($Profile.Args -and $Profile.Args -ne "") {
                $splat.ArgumentList = $Profile.Args
            }

            $process = Start-Process @splat
            Write-KioskLog "Processo avviato: $($Profile.Name) (PID: $($process.Id))"
            return $process
        }
        catch {
            Write-KioskLog "ERRORE avvio (tentativo $attempt): $_" "ERROR"
            Start-Sleep -Seconds 3
        }
    }

    Write-KioskLog "CRITICO: Impossibile avviare $($Profile.Name) dopo $MaxRetries tentativi" "ERROR"
    return $null
}

# ============================================================
#  MAIN
# ============================================================

Write-KioskLog "========== KIOSK AVVIO =========="
Write-KioskLog "Profilo: $AppProfile"
Write-KioskLog "Utente:  $env:USERNAME"
Write-KioskLog "PC:      $env:COMPUTERNAME"

$currentProfile = $AppProfiles[$AppProfile]
if (-not $currentProfile) {
    Write-KioskLog "CRITICO: Profilo '$AppProfile' non trovato!" "ERROR"
    Stop-Computer -Force
    exit 1
}

Write-KioskLog "Applicazione: $($currentProfile.Name) -> $($currentProfile.Path)"

# Pausa per stabilizzare il sistema dopo il logon
Start-Sleep -Seconds 2

# Avvia l'applicazione
$appProcess = Start-KioskApp -Profile $currentProfile

if ($null -eq $appProcess) {
    Write-KioskLog "Nessun processo avviato. Spegnimento..." "ERROR"
    Stop-Computer -Force
    exit 1
}

# --- MONITORAGGIO ---
Write-KioskLog "In attesa della chiusura di $($currentProfile.Process)..."

try {
    $appProcess.WaitForExit()
    Write-KioskLog "Processo principale (PID $($appProcess.Id)) terminato (ExitCode: $($appProcess.ExitCode))"
}
catch {
    Write-KioskLog "WARN: Errore WaitForExit: $_" "WARN"
}

# Pulizia processi residui (VLC puo' lasciare figli)
$waitCount = 0
while ($waitCount -lt 30) {
    $remaining = Get-Process -Name $currentProfile.Process -ErrorAction SilentlyContinue
    if (-not $remaining) { break }
    Write-KioskLog "Processi residui '$($currentProfile.Process)': $($remaining.Count)..."
    Start-Sleep -Seconds 1
    $waitCount++
}

$stillRunning = Get-Process -Name $currentProfile.Process -ErrorAction SilentlyContinue
if ($stillRunning) {
    Write-KioskLog "Forza chiusura processi residui..." "WARN"
    $stillRunning | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# --- SHUTDOWN ---
Write-KioskLog "Applicazione chiusa. Spegnimento tra $ShutdownDelay secondi..."
Write-KioskLog "========== KIOSK FINE =========="

Start-Sleep -Seconds $ShutdownDelay
Stop-Computer -Force
