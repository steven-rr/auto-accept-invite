# Renders icons.html with headless Chrome:
#   icons-sheet.png          every option side by side, at four sizes
#   icon-a.png ... icon-d.png  each option alone, 512x512, with transparent corners
# Usage, from anywhere:  powershell -File docs\curseforge\render-icons.ps1
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$profile = Join-Path $env:TEMP "aai-banner-chrome-profile"
$page = "file:///" + $dir.Replace("\", "/") + "/icons.html"

function Render($url, $out, $size, $transparent) {
    if (Test-Path $out) { Remove-Item $out }
    $list = @("--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
        "--window-size=$size", "--user-data-dir=`"$profile`"", "--screenshot=`"$out`"")
    if ($transparent) { $list += "--default-background-color=00000000" }
    Start-Process -FilePath $chrome -Wait -WindowStyle Hidden -ArgumentList ($list + "`"$url`"")
    if (Test-Path $out) { "Wrote $out ($((Get-Item $out).Length) bytes)" } else { "Chrome wrote no file for $out" }
}

Render $page (Join-Path $dir "icons-sheet.png") "1500,1810" $false
foreach ($key in "a", "b", "c", "d") {
    Render "$page`?icon=$key" (Join-Path $dir "icon-$key.png") "512,512" $true
}
