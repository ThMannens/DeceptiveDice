param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$projectPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$godotDataPath = Join-Path $projectPath ".godot"
$headlessLogPath = Join-Path $godotDataPath "headless-tests.log"
$testResultPath = Join-Path $projectPath "tests\headless-test-result.tmp"
$uiSmokeLogPath = Join-Path $godotDataPath "ui-smoke.log"
$uiSmokeResultPath = Join-Path $projectPath "tests\ui-smoke-result.tmp"
$fullMatchLogPath = Join-Path $godotDataPath "full-match-smoke.log"
$fullMatchResultPath = Join-Path $projectPath "tests\full-match-smoke-result.tmp"
$reconnectLogPath = Join-Path $godotDataPath "reconnect-smoke.log"
$reconnectResultPath = Join-Path $projectPath "tests\reconnect-smoke-result.tmp"
$webRtcSmokeLogPath = Join-Path $godotDataPath "webrtc-smoke.log"
$webRtcSmokeResultPath = Join-Path $projectPath "tests\webrtc-smoke-result.tmp"
$importLogPath = Join-Path $godotDataPath "import.log"
$extensionListPath = Join-Path $godotDataPath "extension_list.cfg"
$networkSmokeLogPath = Join-Path $godotDataPath "network-match-smoke.log"
$networkSmokeResultPath = Join-Path $projectPath "tests\network-match-smoke-result.tmp"
$directSmokeLogPath = Join-Path $godotDataPath "direct-match-smoke.log"
$disconnectSmokeLogPath = Join-Path $godotDataPath "direct-disconnect-smoke.log"
$disconnectSmokeResultPath = Join-Path $projectPath "tests\direct-disconnect-result.tmp"
$webRtcTimeoutLogPath = Join-Path $godotDataPath "webrtc-timeout-smoke.log"
$webRtcTimeoutResultPath = Join-Path $projectPath "tests\webrtc-timeout-result.tmp"
$directSmokeResultPath = Join-Path $projectPath "tests\direct-match-smoke-result.tmp"
[System.IO.Directory]::CreateDirectory($godotDataPath) | Out-Null

if (-not $GodotPath) {
    $godotCommand = Get-Command godot, godot4, Godot -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($godotCommand) {
        $GodotPath = $godotCommand.Source
    }
}

if (-not $GodotPath) {
    $localGodotPath = Join-Path $env:LOCALAPPDATA "Programs\Godot\Godot.exe"
    if (Test-Path -LiteralPath $localGodotPath) {
        $GodotPath = $localGodotPath
    }
}

if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath)) {
    throw "Godot was not found. Pass its executable path with -GodotPath."
}

$godotPathItem = Get-Item -LiteralPath $GodotPath
if (-not $godotPathItem.BaseName.EndsWith("_console")) {
    $consoleExecutableName = $godotPathItem.BaseName + "_console" + $godotPathItem.Extension
    $consoleGodotPath = Join-Path $godotPathItem.DirectoryName $consoleExecutableName
    if (Test-Path -LiteralPath $consoleGodotPath) {
        $GodotPath = $consoleGodotPath
    }
}

if (-not (Test-Path -LiteralPath $extensionListPath) -or -not (Select-String -LiteralPath $extensionListPath -SimpleMatch "webrtc_native.gdextension" -Quiet)) {
    & $GodotPath --headless --path $projectPath --import --quit-after 120 --log-file $importLogPath
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

if (Test-Path -LiteralPath $testResultPath) {
    Remove-Item -LiteralPath $testResultPath
}

& $GodotPath --headless --path $projectPath --log-file $headlessLogPath --script "res://tests/run_tests.gd"
$godotExitCode = $LASTEXITCODE

if (-not (Test-Path -LiteralPath $testResultPath)) {
    throw "The headless test process did not produce a result. Godot exit code: $godotExitCode"
}

$testExitCode = [int](Get-Content -Raw -LiteralPath $testResultPath)
if ($godotExitCode -ne 0) {
    exit $godotExitCode
}
if ($testExitCode -ne 0) {
    exit $testExitCode
}

if (Test-Path -LiteralPath $fullMatchResultPath) {
    Remove-Item -LiteralPath $fullMatchResultPath
}

& $GodotPath --headless --path $projectPath --log-file $fullMatchLogPath --script "res://tests/full_match_smoke.gd"
$fullMatchGodotExitCode = $LASTEXITCODE

if (-not (Test-Path -LiteralPath $fullMatchResultPath)) {
    throw "The full-match bot test did not produce a result. Godot exit code: $fullMatchGodotExitCode"
}

$fullMatchExitCode = [int](Get-Content -Raw -LiteralPath $fullMatchResultPath)
if ($fullMatchGodotExitCode -ne 0) {
    exit $fullMatchGodotExitCode
}
if ($fullMatchExitCode -ne 0) {
    exit $fullMatchExitCode
}

if (Test-Path -LiteralPath $uiSmokeResultPath) {
    Remove-Item -LiteralPath $uiSmokeResultPath
}

& $GodotPath --headless --path $projectPath --log-file $uiSmokeLogPath --script "res://tests/ui_smoke.gd"
$uiGodotExitCode = $LASTEXITCODE

if (-not (Test-Path -LiteralPath $uiSmokeResultPath)) {
    throw "The interface smoke test did not produce a result. Godot exit code: $uiGodotExitCode"
}

$uiSmokeExitCode = [int](Get-Content -Raw -LiteralPath $uiSmokeResultPath)
if ($uiGodotExitCode -ne 0) {
    exit $uiGodotExitCode
}
if ($uiSmokeExitCode -ne 0) {
    exit $uiSmokeExitCode
}

if (Test-Path -LiteralPath $webRtcSmokeResultPath) {
    Remove-Item -LiteralPath $webRtcSmokeResultPath
}

& $GodotPath --headless --path $projectPath --log-file $webRtcSmokeLogPath --script "res://tests/webrtc_smoke.gd"
$webRtcGodotExitCode = $LASTEXITCODE

if (-not (Test-Path -LiteralPath $webRtcSmokeResultPath)) {
    throw "The WebRTC smoke test did not produce a result. Godot exit code: $webRtcGodotExitCode"
}

$webRtcSmokeExitCode = [int](Get-Content -Raw -LiteralPath $webRtcSmokeResultPath)
if ($webRtcGodotExitCode -ne 0) {
    exit $webRtcGodotExitCode
}
if ($webRtcSmokeExitCode -ne 0) {
    exit $webRtcSmokeExitCode
}

if (Test-Path -LiteralPath $networkSmokeResultPath) {
    Remove-Item -LiteralPath $networkSmokeResultPath
}

& $GodotPath --headless --path $projectPath --log-file $networkSmokeLogPath --script "res://tests/network_match_smoke.gd"
$networkGodotExitCode = $LASTEXITCODE

if (-not (Test-Path -LiteralPath $networkSmokeResultPath)) {
    throw "The online match smoke test did not produce a result. Godot exit code: $networkGodotExitCode"
}

$networkSmokeExitCode = [int](Get-Content -Raw -LiteralPath $networkSmokeResultPath)
if ($networkGodotExitCode -ne 0) {
    exit $networkGodotExitCode
}
if ($networkSmokeExitCode -ne 0) {
    exit $networkSmokeExitCode
}

if (Test-Path -LiteralPath $webRtcTimeoutResultPath) {
    Remove-Item -LiteralPath $webRtcTimeoutResultPath
}

& $GodotPath --headless --path $projectPath --log-file $webRtcTimeoutLogPath --script "res://tests/webrtc_timeout_smoke.gd"
$webRtcTimeoutGodotExitCode = $LASTEXITCODE

if (-not (Test-Path -LiteralPath $webRtcTimeoutResultPath)) {
    throw "The WebRTC timeout smoke test did not produce a result. Godot exit code: $webRtcTimeoutGodotExitCode"
}

$webRtcTimeoutExitCode = [int](Get-Content -Raw -LiteralPath $webRtcTimeoutResultPath)
if ($webRtcTimeoutGodotExitCode -ne 0) {
    exit $webRtcTimeoutGodotExitCode
}
if ($webRtcTimeoutExitCode -ne 0) {
    exit $webRtcTimeoutExitCode
}

if (Test-Path -LiteralPath $disconnectSmokeResultPath) {
    Remove-Item -LiteralPath $disconnectSmokeResultPath
}

& $GodotPath --headless --path $projectPath --log-file $disconnectSmokeLogPath --script "res://tests/direct_disconnect_smoke.gd"
$disconnectGodotExitCode = $LASTEXITCODE

if (-not (Test-Path -LiteralPath $disconnectSmokeResultPath)) {
    throw "The disconnect smoke test did not produce a result. Godot exit code: $disconnectGodotExitCode"
}

$disconnectSmokeExitCode = [int](Get-Content -Raw -LiteralPath $disconnectSmokeResultPath)
if ($disconnectGodotExitCode -ne 0) {
    exit $disconnectGodotExitCode
}
if ($disconnectSmokeExitCode -ne 0) {
    exit $disconnectSmokeExitCode
}

if (Test-Path -LiteralPath $directSmokeResultPath) {
    Remove-Item -LiteralPath $directSmokeResultPath
}

& $GodotPath --headless --path $projectPath --log-file $directSmokeLogPath --script "res://tests/direct_match_smoke.gd"
$directGodotExitCode = $LASTEXITCODE

if (-not (Test-Path -LiteralPath $directSmokeResultPath)) {
    throw "The direct connection smoke test did not produce a result. Godot exit code: $directGodotExitCode"
}

$directSmokeExitCode = [int](Get-Content -Raw -LiteralPath $directSmokeResultPath)
if ($directGodotExitCode -ne 0) {
    exit $directGodotExitCode
}
if ($directSmokeExitCode -ne 0) {
    exit $directSmokeExitCode
}

if (Test-Path -LiteralPath $reconnectResultPath) {
    Remove-Item -LiteralPath $reconnectResultPath
}

& $GodotPath --headless --path $projectPath --log-file $reconnectLogPath --script "res://tests/reconnect_smoke.gd"
$reconnectGodotExitCode = $LASTEXITCODE

if (-not (Test-Path -LiteralPath $reconnectResultPath)) {
    throw "The reconnection smoke test did not produce a result. Godot exit code: $reconnectGodotExitCode"
}

$reconnectExitCode = [int](Get-Content -Raw -LiteralPath $reconnectResultPath)
if ($reconnectGodotExitCode -ne 0) {
    exit $reconnectGodotExitCode
}
exit $reconnectExitCode
