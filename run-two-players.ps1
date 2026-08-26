# Launches two windowed instances of the game side by side for testing the
# direct online match without needing the editor's multi-instance setting.
#
#   .\run-two-players.ps1
#
# Instance 1 is on the left, instance 2 on the right. Use "Create host offer"
# in one and "Join with offer" in the other, pasting the codes between them.
param(
    [string]$GodotPath = "",
    [int]$Width = 900,
    [int]$Height = 700
)

$ErrorActionPreference = "Stop"
$projectPath = Split-Path -Parent $MyInvocation.MyCommand.Path

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

$resolution = "${Width}x${Height}"

# Both windows are placed on screen so neither hides the other; the codes have
# to be copied between them by hand.
Start-Process -FilePath $GodotPath -ArgumentList @(
    "--path", $projectPath,
    "--resolution", $resolution,
    "--position", "40,80"
)

Start-Process -FilePath $GodotPath -ArgumentList @(
    "--path", $projectPath,
    "--resolution", $resolution,
    "--position", "$($Width + 80),80"
)

Write-Host "Launched two instances at $resolution."
Write-Host "In one window choose 'Create host offer', copy the code, then paste it"
Write-Host "into 'Join with offer' in the other. Copy the answer code back to the host."
