# Runs the whole GUT suite headless, the same way CI does.
#
#   pwsh tools/run_tests.ps1              # everything
#   pwsh tools/run_tests.ps1 -Script res://tests/unit/test_economy_manager.gd
#   pwsh tools/run_tests.ps1 -Test test_kills_pay_into_the_wave_total
#
# Godot is not on PATH on a normal Windows install - the editor is a loose .exe
# wherever it was downloaded to - so this looks for it instead of making every
# contributor remember the path. Set $env:GODOT to skip the search.

[CmdletBinding()]
param(
    # A single test script (res:// path), instead of every directory.
    [string]$Script = "",
    # A single test function by name. Works with or without -Script.
    [string]$Test = "",
    # Import the project first. Needed after pulling new assets, slow otherwise.
    [switch]$Import
)

# Deliberately not "Stop". Under Windows PowerShell 5.1 a native program writing
# to stderr surfaces as a NativeCommandError, and "Stop" turns that into a
# terminating error - so Godot's harmless import chatter killed this script
# before it ever ran a test. Exit codes are checked by hand instead.
$ErrorActionPreference = "Continue"
$projectRoot = Split-Path -Parent $PSScriptRoot

function Find-Godot {
    if ($env:GODOT -and (Test-Path $env:GODOT)) { return $env:GODOT }

    $onPath = Get-Command godot -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    # Newest first: a machine with 4.6 and 4.7 side by side should test on 4.7,
    # which is what project.godot targets and what CI installs.
    $roots = @(
        "$env:USERPROFILE\Documents\Godot",
        "$env:LOCALAPPDATA\Programs\Godot",
        "C:\Program Files\Godot"
    ) | Where-Object { Test-Path $_ }

    foreach ($root in $roots) {
        $found = Get-ChildItem -Path $root -Filter "Godot_v*_win64_console.exe" `
            -Recurse -Depth 2 -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $null
}

$godot = Find-Godot
if (-not $godot) {
    Write-Error @"
No encontre Godot. Pasalo por variable de entorno:

    `$env:GODOT = "C:\ruta\a\Godot_v4.7-stable_win64_console.exe"

La consola (_console.exe) es la que imprime el resultado de los tests en la
terminal; la otra abre su propia ventana y no vas a ver nada aca.
"@
    exit 1
}
Write-Host "godot: $godot" -ForegroundColor DarkGray

if ($Import) {
    # Reimports every asset. Do this when the suite fails on "invalid UID" or on
    # audio buses that are suddenly missing: those are a stale .godot/ cache
    # rather than broken code, and this is the cheap half of the fix (the other
    # half is deleting .godot/imported and .godot/uid_cache.bin first).
    #
    # stderr is left alone on purpose - piping it through PowerShell is what
    # made this step blow up before.
    Write-Host "importando el proyecto..." -ForegroundColor DarkGray
    & $godot --headless --path $projectRoot --import --quit-after 400 | Out-Null
}

# -gexit is what makes the run return to the shell; without it Godot sits on the
# results forever and a CI job (or this script) never finishes.
$gutArgs = @("--headless", "--path", $projectRoot, "-s", "addons/gut/gut_cmdln.gd", "-gexit")
if ($Script) { $gutArgs += @("-gtest=$Script") }
if ($Test) { $gutArgs += @("-gunit_test_name=$Test") }

& $godot @gutArgs
$code = $LASTEXITCODE

# GUT exits non-zero on a failing test, which is the signal worth surfacing -
# but the engine also exits non-zero on unrelated shutdown noise, so the line
# above the totals is what to read, not just this number.
if ($code -ne 0) {
    Write-Host "`nGUT termino con codigo $code (hay tests en rojo, o el motor se quejo al salir)." `
        -ForegroundColor Yellow
}
exit $code
