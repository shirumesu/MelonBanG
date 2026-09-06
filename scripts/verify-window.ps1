param(
  [string]$Executable = 'desktop/build/windows/x64/runner/Release/melonbang.exe',
  [string]$Media = 'temp/verification/native-hevc-10bit.mkv'
)

$ErrorActionPreference = 'Stop'
$trialPath = (Resolve-Path -LiteralPath $Executable).Path
$trialData = Join-Path ([IO.Path]::GetTempPath()) ('melonbang-window-' + [guid]::NewGuid())
$env:MELONBANG_DATA_DIR = $trialData
$env:MELONBANG_CONFIG_DIR = $trialData
$env:MELONBANG_MUTE_AUDIO = '1'
$childIds = @()
$startOptions = @{ FilePath = $trialPath; WorkingDirectory = (Split-Path $trialPath); WindowStyle = 'Hidden'; PassThru = $true }
if ($Media) {
  $mediaPath = (Resolve-Path -LiteralPath $Media).Path
  $startOptions.ArgumentList = '"' + $mediaPath + '"'
}
$trialProcess = Start-Process @startOptions
try {
  Start-Sleep -Seconds 8
  $trialProcess.Refresh()
  if ($trialProcess.HasExited -or $trialProcess.MainWindowHandle -eq 0) {
    throw 'The packaged application did not show its window.'
  }
  $childIds = @(Get-CimInstance Win32_Process -Filter ('ParentProcessId = ' + $trialProcess.Id) | Select-Object -ExpandProperty ProcessId)
  if ($childIds.Count -eq 0) { throw 'The bundled service was not started.' }
  if (-not $trialProcess.CloseMainWindow()) { throw 'Could not request normal window close.' }
  if (-not $trialProcess.WaitForExit(8000)) { throw 'The application did not exit in eight seconds.' }
  if ($trialProcess.ExitCode -ne 0) { throw ('Native shutdown failed: ' + $trialProcess.ExitCode) }
  foreach ($childId in $childIds) {
    if (Get-Process -Id $childId -ErrorAction SilentlyContinue) { throw 'The application left its service running.' }
  }
  Write-Output 'Packaged window: launch, service startup, normal close, and child cleanup passed.'
} finally {
  if (-not $trialProcess.HasExited) { $trialProcess.Kill(); $trialProcess.WaitForExit() }
  foreach ($childId in $childIds) {
    Stop-Process -Id $childId -ErrorAction SilentlyContinue
  }
}
