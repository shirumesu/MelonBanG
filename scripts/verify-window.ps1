param(
  [string]$Executable = 'build/windows/x64/runner/Release/melonbang.exe',
  [string]$Media = ''
)

$ErrorActionPreference = 'Stop'
$trialPath = (Resolve-Path -LiteralPath $Executable).Path
$trialData = Join-Path ([IO.Path]::GetTempPath()) ('melonbang-window-' + [guid]::NewGuid())
$previousDataDirectory = $env:MELONBANG_DATA_DIR
$previousMute = $env:MELONBANG_MUTE_AUDIO
$env:MELONBANG_DATA_DIR = $trialData
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
  $databasePath = Join-Path $trialData 'melonbang.sqlite'
  if (-not (Test-Path -LiteralPath $databasePath) -or (Get-Item -LiteralPath $databasePath).Length -eq 0) {
    throw 'The packaged application did not initialize its Dart database.'
  }
  $childIds = @(Get-CimInstance Win32_Process -Filter ('ParentProcessId = ' + $trialProcess.Id) | Select-Object -ExpandProperty ProcessId)
  if ($childIds.Count -ne 0) { throw 'The native application unexpectedly started a child process.' }
  if (-not $trialProcess.CloseMainWindow()) { throw 'Could not request normal window close.' }
  if (-not $trialProcess.WaitForExit(8000)) { throw 'The application did not exit in eight seconds.' }
  if ($trialProcess.ExitCode -ne 0) { throw ('Native shutdown failed: ' + $trialProcess.ExitCode) }
  foreach ($childId in $childIds) {
    if (Get-Process -Id $childId -ErrorAction SilentlyContinue) { throw 'The application left its service running.' }
  }
  Write-Output 'Packaged Flutter app: launch, no child runtime, and normal close passed.'
} finally {
  if (-not $trialProcess.HasExited) { $trialProcess.Kill(); $trialProcess.WaitForExit() }
  foreach ($childId in $childIds) {
    Stop-Process -Id $childId -ErrorAction SilentlyContinue
  }
  $env:MELONBANG_DATA_DIR = $previousDataDirectory
  $env:MELONBANG_MUTE_AUDIO = $previousMute
  if (Test-Path -LiteralPath $trialData) {
    $resolvedTrialData = (Resolve-Path -LiteralPath $trialData).Path
    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolvedTrialData.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase)) {
      throw 'Unexpected verification data path.'
    }
    Remove-Item -LiteralPath $resolvedTrialData -Recurse -Force
  }
}
