# Renderiza un arquetipo de enemigo a PNG, sin dejar rastro en el proyecto.
#
#   pwsh tools/run_preview.ps1 rusher
#   pwsh tools/run_preview.ps1 rusher walk
#   pwsh tools/run_preview.ps1 rusher walk front
#   pwsh tools/run_preview.ps1 rusher measure
#
# El script de adentro (preview_enemy_model.gd) necesita ventana para renderizar,
# y en esa pasada Godot reescanea el proyecto y re-serializa escenas y recursos
# por su cuenta. Correrlo a mano ya se llevo puesto el prewarm_count del
# EnemySpawner dos veces. Este envoltorio existe para que eso no vuelva a pasar:
# lo que la corrida reescriba se revierte al terminar.

# PositionalBinding a $false para que lo suelto en la linea de comandos caiga
# entero en PreviewArgs. Sin eso, "rusher walk" se repartia entre parametros y
# Godot recibia "rusher" como resolucion.
[CmdletBinding(PositionalBinding = $false)]
param(
    # rusher / ranger / elite / healer / summoner, mas los modos walk, front y
    # measure. Se pasan tal cual al script de Godot.
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PreviewArgs = @("rusher"),
    # Resolucion de la foto. Cuatro copias entran comodas en 1400x500.
    [string]$Resolution = "1400x500",
    [switch]$KeepIncidentalChanges
)

$ErrorActionPreference = "Continue"
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "git_guard.ps1")

$godot = $env:GODOT
if (-not $godot -or -not (Test-Path $godot)) {
    $onPath = Get-Command godot -ErrorAction SilentlyContinue
    if ($onPath) {
        $godot = $onPath.Source
    } else {
        $found = Get-ChildItem -Path "$env:USERPROFILE\Documents\Godot" `
            -Filter "Godot_v*_win64_console.exe" -Recurse -Depth 2 -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($found) { $godot = $found.FullName }
    }
}
if (-not $godot) {
    Write-Error 'No encontre Godot. Pasalo por $env:GODOT.'
    exit 1
}

$treeBefore = $null
if (-not $KeepIncidentalChanges) {
    $treeBefore = Get-DirtyPaths -RepoRoot $projectRoot
}

# Sin --headless a proposito: la foto sale del viewport, y sin ventana no hay
# viewport del que sacarla.
& $godot --path $projectRoot --resolution $Resolution `
    -s res://tools/preview_enemy_model.gd -- @PreviewArgs
$code = $LASTEXITCODE

Restore-IncidentalChanges -RepoRoot $projectRoot -Before $treeBefore
exit $code
