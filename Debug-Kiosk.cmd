@echo off
REM ============================================================
REM  Kiosk DEBUG Launcher
REM  Solo per test manuali. In produzione si usa Start-Kiosk.vbs
REM  Questo mostra la console per vedere eventuali errori.
REM ============================================================

echo.
echo ========================================
echo   KIOSK DEBUG MODE
echo   Ctrl+C per interrompere lo shutdown
echo ========================================
echo.

C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -NoLogo -File "C:\Kiosk\Start-Kiosk.ps1"

echo.
echo [DEBUG] PowerShell terminato (exit code: %ERRORLEVEL%)
echo [DEBUG] Shutdown tra 15 secondi - Ctrl+C per annullare
timeout /t 15
shutdown /s /t 5 /f
