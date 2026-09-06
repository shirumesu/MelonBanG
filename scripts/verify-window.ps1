param(
  [string]$Executable = 'build/windows/x64/runner/Release/melonbang.exe',
  [string]$Media = ''
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path $PSScriptRoot
$executablePath = if ([IO.Path]::IsPathRooted($Executable)) { $Executable } else { Join-Path $projectDirectory $Executable }
$executablePath = (Resolve-Path -LiteralPath $executablePath).Path
$verificationData = Join-Path ([IO.Path]::GetTempPath()) ('melonbang-window-' + [guid]::NewGuid())
$previousDataDirectory = $env:MELONBANG_DATA_DIR
$previousMute = $env:MELONBANG_MUTE_AUDIO
$applicationProcess = $null
$childIds = @()
try {
  $env:MELONBANG_DATA_DIR = $verificationData
  $env:MELONBANG_MUTE_AUDIO = '1'
  $startOptions = @{ FilePath = $executablePath; WorkingDirectory = (Split-Path $executablePath); WindowStyle = 'Hidden'; PassThru = $true }
  if ($Media) {
    $mediaPath = (Resolve-Path -LiteralPath $Media).Path
    $startOptions.ArgumentList = '"' + $mediaPath + '"'
  }
  $applicationProcess = Start-Process @startOptions
  $databasePath = Join-Path $verificationData 'melonbang.sqlite'
  $startupDeadline = [DateTime]::UtcNow.AddSeconds(20)
  do {
    Start-Sleep -Milliseconds 250
    $applicationProcess.Refresh()
    if ($applicationProcess.HasExited) { throw 'The packaged application exited during startup.' }
    $databaseReady = (Test-Path -LiteralPath $databasePath) -and (Get-Item -LiteralPath $databasePath).Length -gt 0
  } while (($applicationProcess.MainWindowHandle -eq 0 -or -not $databaseReady) -and [DateTime]::UtcNow -lt $startupDeadline)
  if ($applicationProcess.MainWindowHandle -eq 0) { throw 'The packaged application did not show its window.' }
  if (-not $databaseReady) { throw 'The packaged application did not initialize its Dart database.' }
  # Allow media initialization before exercising active-playback shutdown.
  Start-Sleep -Seconds 3
  $childIds = @(Get-CimInstance Win32_Process -Filter ('ParentProcessId = ' + $applicationProcess.Id) | Select-Object -ExpandProperty ProcessId)
  if ($childIds.Count -ne 0) { throw 'The native application unexpectedly started a child process.' }
  if (-not $applicationProcess.CloseMainWindow()) { throw 'Could not request normal window close.' }
  if (-not $applicationProcess.WaitForExit(8000)) { throw 'The application did not exit in eight seconds.' }
  if ($applicationProcess.ExitCode -ne 0) { throw ('Native shutdown failed: ' + $applicationProcess.ExitCode) }
  Write-Output 'Packaged Flutter app: launch, no child runtime, and normal close passed.'
} finally {
  $env:MELONBANG_DATA_DIR = $previousDataDirectory
  $env:MELONBANG_MUTE_AUDIO = $previousMute
  if ($applicationProcess -and -not $applicationProcess.HasExited) {
    $applicationProcess.Kill()
    $applicationProcess.WaitForExit()
  }
  foreach ($childId in $childIds) {
    Stop-Process -Id $childId -ErrorAction SilentlyContinue
  }
  if (Test-Path -LiteralPath $verificationData) {
    $resolvedVerificationData = (Resolve-Path -LiteralPath $verificationData).Path
    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolvedVerificationData.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase)) {
      throw 'Unexpected verification data path.'
    }
    Remove-Item -LiteralPath $resolvedVerificationData -Recurse -Force
  }
}
