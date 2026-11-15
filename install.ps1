# mimray installer for Windows (x64). Verifies the download against SHA256SUMS.
#   irm https://raw.githubusercontent.com/mimzeslami/mimray/main/install.ps1 | iex
# Installs to %LOCALAPPDATA%\Programs\mimray (no admin needed) and adds
# Start Menu + Desktop shortcuts. Env: $env:MIMRAY_ZIP = local zip to install instead.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue' # makes Invoke-WebRequest much faster
$repo = 'mimzeslami/mimray'
function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan }

if (-not [Environment]::Is64BitOperatingSystem) { throw 'mimray needs 64-bit Windows.' }

$tmp = Join-Path $env:TEMP ("mimray-" + [guid]::NewGuid())
New-Item -ItemType Directory $tmp | Out-Null
try {
  if ($env:MIMRAY_ZIP) {
    $zip = $env:MIMRAY_ZIP
    Say "Using local build $zip"
  } else {
    Say 'Finding the latest mimray release'
    $rel = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
    $asset = $rel.assets | Where-Object { $_.name -like '*-windows-x64.zip' } | Select-Object -First 1
    $sums = $rel.assets | Where-Object { $_.name -eq 'SHA256SUMS' } | Select-Object -First 1
    if (-not $asset -or -not $sums) { throw 'No Windows release yet.' }
    $zip = Join-Path $tmp $asset.name
    Say "Downloading $($asset.name)"
    Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing
    $sumsText = (Invoke-WebRequest $sums.browser_download_url -UseBasicParsing).Content
    if ($sumsText -is [byte[]]) { $sumsText = [Text.Encoding]::UTF8.GetString($sumsText) }
    $want = ($sumsText -split "`n" | Where-Object { $_ -match " $([regex]::Escape($asset.name))\s*$" }) -split '\s+' | Select-Object -First 1
    $got = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
    Say 'Verifying checksum'
    if (-not $want -or $got -ne $want.ToLower()) { throw 'Checksum mismatch, aborting (download corrupted or tampered).' }
  }

  $dir = Join-Path $env:LOCALAPPDATA 'Programs\mimray'
  Get-Process mimray -ErrorAction SilentlyContinue | Stop-Process -Force
  if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
  New-Item -ItemType Directory $dir -Force | Out-Null
  Expand-Archive $zip -DestinationPath $dir -Force
  $exe = Join-Path $dir 'mimray.exe'
  if (-not (Test-Path $exe) -or -not (Test-Path (Join-Path $dir 'sing-box.exe'))) { throw 'Package is incomplete.' }
  Get-ChildItem $dir -Recurse | Unblock-File # drop the "downloaded from internet" mark

  $sh = New-Object -ComObject WScript.Shell
  foreach ($lnk in @(
      (Join-Path ([Environment]::GetFolderPath('Programs')) 'mimray.lnk'),
      (Join-Path ([Environment]::GetFolderPath('Desktop')) 'mimray.lnk'))) {
    $s = $sh.CreateShortcut($lnk)
    $s.TargetPath = $exe
    $s.WorkingDirectory = $dir
    $s.Description = 'mimray VPN'
    $s.Save()
  }

  Say "Installed to $dir"
  Write-Host @"

  Run it:  open "mimray" from the Start Menu or your Desktop.
  Then:    + Add -> Add subscription (or Import from clipboard / Scan QR),
           pick a server or Auto, and flip the switch.
           Windows asks for permission (UAC) when connecting - that's needed for the tunnel.

  Update:  run this command again.
  Remove:  Remove-Item -Recurse "$dir", "$env:APPDATA\mimray";
           Remove-Item "$([Environment]::GetFolderPath('Programs'))\mimray.lnk", "$([Environment]::GetFolderPath('Desktop'))\mimray.lnk"

"@
  Start-Process $exe
} finally {
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
