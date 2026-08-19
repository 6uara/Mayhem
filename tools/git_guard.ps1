# Deja el working tree exactamente como lo encontro.
#
# Existe por un problema concreto: correr Godot sobre el proyecto puede
# re-serializar .tscn y .tres por su cuenta - agrega uid= a los ext_resource y,
# peor, borra toda propiedad cuyo valor sea igual a su default. Asi es como
# game.tscn perdio dos veces el prewarm_count del EnemySpawner, que es el
# prewarm del pool de enemigos: un cambio que nadie pidio, en un archivo que
# nadie estaba tocando, escondido dentro de un commit sobre otra cosa.
#
# La regla es simple: lo que ya estaba sucio antes de correr es tuyo y no se
# toca. Lo que estaba limpio y quedo sucio despues lo escribio la corrida, y eso
# se revierte. Un archivo nuevo sin trackear no se borra nunca - se avisa y se
# deja, porque puede ser algo que quisiste generar.

function Get-DirtyPaths {
    <#
        Rutas que git ve modificadas ahora mismo, como un hashtable ruta -> estado.
        Devuelve $null cuando no hay git o no estamos en un repo, que es la senal
        para que el guard se desactive en vez de romper la corrida.
    #>
    param([string]$RepoRoot)

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    $inside = & git -C $RepoRoot rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0 -or $inside -ne "true") { return $null }

    $paths = @{}
    foreach ($line in (& git -C $RepoRoot status --porcelain=v1 --untracked-files=all)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $state = $line.Substring(0, 2)
        $path = $line.Substring(3)
        # Un rename se reporta como "viejo -> nuevo"; el que importa es el nuevo.
        if ($path -match " -> ") { $path = ($path -split " -> ")[-1] }
        $paths[$path.Trim('"')] = $state
    }
    return $paths
}

function Restore-IncidentalChanges {
    <#
        Compara contra el estado previo y revierte lo que escribio la corrida.
        Imprime lo que hizo: un revert silencioso es tan malo como el cambio.
    #>
    param(
        [string]$RepoRoot,
        $Before
    )

    if ($null -eq $Before) { return }
    $after = Get-DirtyPaths -RepoRoot $RepoRoot
    if ($null -eq $after) { return }

    $reverted = @()
    $created = @()
    foreach ($path in $after.Keys) {
        if ($Before.ContainsKey($path)) { continue }
        # Comparacion exacta, no -like: en PowerShell "?" es comodin de un
        # caracter, asi que un patron con ? adentro matcheaba cualquier estado y
        # el guard trataba de nuevo todo lo que veia, sin revertir nada.
        if ($after[$path] -eq "??") { $created += $path; continue }
        & git -C $RepoRoot checkout -- $path 2>$null
        if ($LASTEXITCODE -eq 0) { $reverted += $path }
    }

    if ($reverted.Count -gt 0) {
        Write-Host "`nGodot reescribio archivos que vos no tocaste. Revertidos:" -ForegroundColor Yellow
        foreach ($path in ($reverted | Sort-Object)) { Write-Host "  $path" -ForegroundColor Yellow }
    }
    if ($created.Count -gt 0) {
        Write-Host "`nLa corrida dejo archivos nuevos (no se borran solos):" -ForegroundColor DarkYellow
        foreach ($path in ($created | Sort-Object)) { Write-Host "  $path" -ForegroundColor DarkYellow }
    }
}
