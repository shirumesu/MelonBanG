# Builds the Windows release files into dist/:
#   MelonBanG-<version>-windows-x64.zip        portable copy, also the update package
#   MelonBanG-<version>-windows-x64-setup.exe  installer
#   manifest.json (+ manifest.json.sig)        what the in-app updater trusts
param(
  [string]$ConfigurationFile = '.env.service.json',
  # PEM private key for the manifest signature; without it the release cannot
  # be offered to the in-app updater.
  [string]$SigningKey,
  # Standard NSIS install (winget install NSIS.NSIS) and the OpenSSL bundled
  # with Git for Windows, on developer machines and GitHub runners alike.
  [string]$Makensis = "${env:ProgramFiles(x86)}\NSIS\makensis.exe",
  [string]$OpenSsl = "$env:ProgramFiles\Git\usr\bin\openssl.exe"
)
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path $PSScriptRoot
$flutterCommand = if ($env:FLUTTER_ROOT) { Join-Path $env:FLUTTER_ROOT 'bin/flutter.bat' } else { 'flutter' }
Push-Location $projectDirectory
try {
  & (Join-Path $PSScriptRoot 'build.ps1') -ConfigurationFile $ConfigurationFile
  $version = (Select-String -LiteralPath 'pubspec.yaml' -Pattern '^version:\s*([^+\s]+)').Matches[0].Groups[1].Value
  $releaseDirectory = Join-Path $projectDirectory 'build/windows/x64/runner/Release'

  Push-Location 'installer'
  try {
    & $flutterCommand pub get
    if ($LASTEXITCODE -ne 0) { throw 'Installer dependency resolution failed.' }
    & $flutterCommand build windows --release "--build-name=$version" "--dart-define=MELONBANG_VERSION=$version"
    if ($LASTEXITCODE -ne 0) { throw 'Installer build failed.' }
  } finally { Pop-Location }
  # The installer links the MSVC runtime dynamically too, and runs before the
  # program's copy of it is unpacked.
  $setupDirectory = Join-Path $projectDirectory 'installer/build/windows/x64/runner/Release'
  foreach ($runtime in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    Copy-Item -LiteralPath (Join-Path $releaseDirectory $runtime) -Destination $setupDirectory
  }
  # The installer also uninstalls: as uninstall.exe it shares the program's
  # engine, with its own Dart files in "setup".
  Copy-Item -LiteralPath (Join-Path $setupDirectory 'melonbang_setup.exe') -Destination (Join-Path $releaseDirectory 'uninstall.exe')
  $uninstallData = Join-Path $releaseDirectory 'setup'
  Remove-Item -LiteralPath $uninstallData -Recurse -Force -ErrorAction Ignore
  Copy-Item -LiteralPath (Join-Path $setupDirectory 'data') -Destination $uninstallData -Recurse

  $dist = Join-Path $projectDirectory 'dist'
  Remove-Item -LiteralPath $dist -Recurse -Force -ErrorAction Ignore
  New-Item -ItemType Directory $dist | Out-Null
  $archiveName = "MelonBanG-$version-windows-x64.zip"
  $archive = Join-Path $dist $archiveName
  Compress-Archive -Path (Join-Path $releaseDirectory '*') -DestinationPath $archive

  $numericVersion = ($version -split '-')[0] + '.0'
  & $Makensis /V2 "/DVERSION=$version" "/DNUMERIC_VERSION=$numericVersion" `
    "/DSETUP_DIR=$setupDirectory" `
    "/DPAYLOAD=$archive" "/DOUTFILE=$(Join-Path $dist "MelonBanG-$version-windows-x64-setup.exe")" `
    (Join-Path $projectDirectory 'installer/setup.nsi')
  if ($LASTEXITCODE -ne 0) { throw 'Setup packaging failed.' }

  $manifest = [ordered]@{
    version = $version
    platforms = [ordered]@{
      'windows-x64' = [ordered]@{
        urls = @("https://github.com/shirumesu/MelonBanG/releases/download/v$version/$archiveName")
        sha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
        size = (Get-Item -LiteralPath $archive).Length
      }
    }
  }
  $manifestPath = Join-Path $dist 'manifest.json'
  [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 5 -Compress), [Text.UTF8Encoding]::new($false))
  if ($SigningKey) {
    & $OpenSsl dgst -sha256 -sign $SigningKey -out "$manifestPath.sig" $manifestPath
    if ($LASTEXITCODE -ne 0) { throw 'Manifest signing failed.' }
  } else {
    Write-Warning 'No signing key: the in-app updater will not accept this release.'
  }
  Get-ChildItem -LiteralPath $dist | ForEach-Object { $_.FullName }
} finally { Pop-Location }
