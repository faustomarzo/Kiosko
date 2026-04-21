' ============================================================
'  Kiosk Silent Launcher v3.0
'  Questo file e' il valore Shell nel registry.
'  wscript.exe non crea nessuna finestra visibile.
' ============================================================

Set WshShell = CreateObject("WScript.Shell")
Set FSO = CreateObject("Scripting.FileSystemObject")

' Cartella log
Dim logFolder : logFolder = "C:\Kiosk\Logs"
If Not FSO.FolderExists(logFolder) Then FSO.CreateFolder(logFolder)

' Log avvio
Dim logFile : logFile = logFolder & "\launcher.log"
Set logStream = FSO.OpenTextFile(logFile, 8, True)
logStream.WriteLine "[" & Now & "] =================================="
logStream.WriteLine "[" & Now & "] Kiosk VBS launcher avviato"
logStream.WriteLine "[" & Now & "] Utente: " & WshShell.ExpandEnvironmentStrings("%USERNAME%")

' Pausa per dare tempo ai driver video/rete
logStream.WriteLine "[" & Now & "] Attesa inizializzazione sistema (8 sec)..."
logStream.Close
WScript.Sleep 8000

' Avvia PowerShell COMPLETAMENTE NASCOSTO (0 = hidden, True = attendi fine)
Dim psCmd
psCmd = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" & _
        " -ExecutionPolicy Bypass -NoProfile -NoLogo -WindowStyle Hidden" & _
        " -File ""C:\Kiosk\Start-Kiosk.ps1"""

Set logStream = FSO.OpenTextFile(logFile, 8, True)
logStream.WriteLine "[" & Now & "] Avvio: " & psCmd
logStream.Close

' Il terzo parametro True = WshShell.Run attende la fine del processo
' Il secondo parametro 0 = finestra nascosta
Dim exitCode
exitCode = WshShell.Run(psCmd, 0, True)

' Se arriviamo qui, PowerShell e' terminato
Set logStream = FSO.OpenTextFile(logFile, 8, True)
logStream.WriteLine "[" & Now & "] PowerShell terminato (exit: " & exitCode & ")"
logStream.WriteLine "[" & Now & "] Safety shutdown..."
logStream.Close

' Safety net: spegni se PowerShell non l'ha gia' fatto
WshShell.Run "shutdown /s /t 10 /f /c ""Kiosk: sessione terminata""", 0, False
