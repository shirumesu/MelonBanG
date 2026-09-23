param(
  [switch]$Archive,
  [switch]$Development,
  [string]$ConfigurationFile = '.env.service.json'
)
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path $PSScriptRoot
$flutterCommand = if ($env:FLUTTER_ROOT) { Join-Path $env:FLUTTER_ROOT 'bin/flutter.bat' } else { 'flutter' }
Push-Location $projectDirectory
try {
  $buildArguments = @('build', 'windows', '--release')
  if (Test-Path -LiteralPath $ConfigurationFile) {
    try {
      $configuration = Get-Content -LiteralPath $ConfigurationFile -Raw | ConvertFrom-Json
    } catch {
      throw 'Service configuration must be a valid JSON object; use .env.service.example.json as the template.'
    }
    if (-not ($configuration -is [pscustomobject])) {
      throw 'Service configuration must be a JSON object.'
    }
    if (-not $Development) {
      foreach ($key in @('BANGUMI_CLIENT_ID', 'BANGUMI_CLIENT_SECRET', 'DANDANPLAY_APP_ID', 'DANDANPLAY_APP_SECRET')) {
        $value = $configuration.PSObject.Properties[$key].Value
        if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) {
          throw "Missing build setting $key. Fill $ConfigurationFile or use -Development for a build with optional services disabled."
        }
      }
    }
    $buildArguments += '--dart-define-from-file=' + (Resolve-Path -LiteralPath $ConfigurationFile).Path
  } elseif (-not $Development) {
    throw 'Copy .env.service.example.json to .env.service.json and fill the service registrations, or pass -ConfigurationFile. Use -Development to build without them.'
  }
  & $flutterCommand pub get
  if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
  & $flutterCommand @buildArguments
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
