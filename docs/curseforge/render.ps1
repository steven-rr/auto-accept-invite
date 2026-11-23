# Renders banner.html to banner.png (1600x480) with headless Chrome.
# Usage, from anywhere:  powershell -File docs\curseforge\render.ps1
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$out = Join-Path $dir "banner.png"
$profile = Join-Path $env:TEMP "aai-banner-chrome-profile"
if (Test-Path $out) { Remove-Item $out }
$page = "file:///" + $dir.Replace("\", "/") + "/banner.html"
Start-Process -FilePath $chrome -Wait -WindowStyle Hidden -ArgumentList @(
    "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
    "--window-size=1600,480", "--user-data-dir=`"$profile`"", "--screenshot=`"$out`"", "`"$page`""
)
if (Test-Path $out) { "Wrote $out ($((Get-Item $out).Length) bytes)" } else { "Chrome wrote no file." }
