param([switch]$Archive)
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path $PSScriptRoot
$flutterCommand = if ($env:FLUTTER_ROOT) { Join-Path $env:FLUTTER_ROOT 'bin/flutter.bat' } else { 'flutter' }
Push-Location $projectDirectory
try {
  & $flutterCommand pub get
  if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
  & $flutterCommand build windows --release
  if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
  $releaseDirectory = Join-Path $projectDirectory 'build/windows/x64/runner/Release'
  Copy-Item -LiteralPath (Join-Path $projectDirectory 'THIRD_PARTY.md') -Destination $releaseDirectory
  $licensesDirectory = Join-Path $releaseDirectory 'licenses'
  New-Item -ItemType Directory -Force $licensesDirectory | Out-Null
  foreach ($pluginName in @('media_kit_video', 'libtorrent_flutter')) {
    Copy-Item -LiteralPath (Join-Path $projectDirectory "vendor/$pluginName/LICENSE") -Destination (Join-Path $licensesDirectory "$pluginName.txt")
  }
  $nativeShare = Join-Path $projectDirectory 'build/windows/x64/vcpkg_installed/x64-windows-static-md/share'
  Get-ChildItem -LiteralPath $nativeShare -Directory | ForEach-Object {
    $nativeLicense = Join-Path $_.FullName 'copyright'
    if (Test-Path -LiteralPath $nativeLicense) {
      Copy-Item -LiteralPath $nativeLicense -Destination (Join-Path $licensesDirectory ($_.Name + '.txt'))
    }
  }
  if ($Archive) {
    New-Item -ItemType Directory -Force 'dist' | Out-Null
    Compress-Archive -Path (Join-Path $releaseDirectory '*') -DestinationPath 'dist/melonbang-windows-x64.zip' -Force
  }
  Write-Output (Join-Path $releaseDirectory 'melonbang.exe')
} finally { Pop-Location }
