$ErrorActionPreference = 'Stop'

$projectDirectory = Split-Path $PSScriptRoot
$dartCommand = if ($env:FLUTTER_ROOT) { Join-Path $env:FLUTTER_ROOT 'bin/dart.bat' } else { 'dart' }

Push-Location $projectDirectory
try {
  & $dartCommand run scripts/flutter.dart @args
  exit $LASTEXITCODE
} finally {
  Pop-Location
}
