<#
.SYNOPSIS
Health check for the codex-os wiring. Read-only.

.DESCRIPTION
Reports: skill link state, orphaned junctions left in ~/.codex/skills, drift between
global/AGENTS.md and ~/.codex/AGENTS.md, loop definitions whose cwd is missing, and whether
codex.exe can be resolved.

Deliberately standalone -- it does NOT dot-source _common.ps1, and it avoids .NET type literals and
method calls. Codex runs commands in a sandbox where PowerShell is in ConstrainedLanguage mode,
which forbids both; this script has to stay runnable from inside a loop.

Exit code 0 = clean, 1 = something needs attention.

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\doctor.ps1
#>
[CmdletBinding()]
param()

$root       = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$codexHome  = $env:CODEX_HOME
if (-not $codexHome) { $codexHome = Join-Path $env:USERPROFILE '.codex' }
$skillsSrc  = Join-Path $root 'skills'
$skillsDest = Join-Path $codexHome 'skills'
$findings   = New-Object System.Collections.ArrayList

function Add-Finding {
    param([string]$Area, [string]$Item, [string]$Status, [string]$Detail)
    [void]$findings.Add([pscustomobject]@{ Area = $Area; Item = $Item; Status = $Status; Detail = $Detail })
}

# Link state via the LinkType/Target properties rather than [IO.FileAttributes], which is not an
# allowed type literal under ConstrainedLanguage.
function Get-LinkInfo {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $item = Get-Item -LiteralPath $Path -Force
    $type = $item.LinkType
    $target = $item.Target
    if ($target -is [array]) { $target = $target[0] }
    return [pscustomobject]@{ IsLink = [bool]$type; Type = $type; Target = $target }
}

function Test-SamePath {
    param([string]$A, [string]$B)
    if (-not $A -or -not $B) { return $false }
    return ($A.TrimEnd('\') -ieq $B.TrimEnd('\'))
}

function Get-HashOrNull {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

# Flat `key: value` frontmatter only; returns @{ Meta = @{}; Body = '' }.
function Read-FrontMatterFile {
    param([string]$Path)
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    $meta = @{}
    $bodyStart = 0
    if ($lines.Count -gt 0 -and $lines[0].Trim() -eq '---') {
        $i = 1
        while ($i -lt $lines.Count -and $lines[$i].Trim() -ne '---') {
            if ($lines[$i] -match '^\s*([A-Za-z0-9_\-]+)\s*:\s*(.*)$') {
                $meta[$matches[1]] = $matches[2].Trim().Trim("'").Trim('"')
            }
            $i++
        }
        $bodyStart = $i + 1
    }
    $body = ''
    if ($bodyStart -lt $lines.Count) { $body = ($lines[$bodyStart..($lines.Count - 1)] -join "`n").Trim() }
    return @{ Meta = $meta; Body = $body }
}

# --- codex binary ------------------------------------------------------------------------------

$codexCmd = Get-Command codex -ErrorAction SilentlyContinue
if ($codexCmd) {
    Add-Finding 'codex' 'codex.exe' 'OK' $codexCmd.Source
} else {
    $binRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
    $found = $null
    if (Test-Path $binRoot) {
        $found = Get-ChildItem -Path $binRoot -Filter 'codex.exe' -Recurse -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }
    if ($found) { Add-Finding 'codex' 'codex.exe' 'OK' $found.FullName }
    else        { Add-Finding 'codex' 'codex.exe' 'FAIL' 'not on PATH and not found under LOCALAPPDATA' }
}

# --- skills ------------------------------------------------------------------------------------

$expected = @{}

foreach ($skill in (Get-ChildItem -Path $skillsSrc -Directory -ErrorAction SilentlyContinue)) {
    if ($skill.Name -like '.*') { continue }
    $expected[$skill.Name] = $true
    $link = Join-Path $skillsDest $skill.Name

    if (-not (Test-Path (Join-Path $skill.FullName 'SKILL.md'))) {
        Add-Finding 'skills' $skill.Name 'FAIL' 'missing SKILL.md'
        continue
    }

    $fm = Read-FrontMatterFile (Join-Path $skill.FullName 'SKILL.md')
    if (-not $fm.Meta.ContainsKey('name') -or -not $fm.Meta.ContainsKey('description')) {
        Add-Finding 'skills' $skill.Name 'FAIL' 'frontmatter needs both name and description'
    } elseif ($fm.Meta['name'] -ne $skill.Name) {
        Add-Finding 'skills' $skill.Name 'FAIL' ("frontmatter name is '{0}'" -f $fm.Meta['name'])
    }

    $info = Get-LinkInfo $link
    if ($null -eq $info) {
        Add-Finding 'skills' $skill.Name 'MISSING' 'not linked -- run sync.ps1'
    } elseif (-not $info.IsLink) {
        Add-Finding 'skills' $skill.Name 'CONFLICT' 'real directory in ~/.codex/skills'
    } elseif (Test-SamePath $info.Target $skill.FullName) {
        Add-Finding 'skills' $skill.Name 'OK' 'junction current'
    } else {
        Add-Finding 'skills' $skill.Name 'DRIFT' ("points at '{0}'" -f $info.Target)
    }
}

# --- vendor skills -------------------------------------------------------------------------------

$vendorRoot  = Join-Path $root 'vendor'
$enabledFile = Join-Path $vendorRoot 'enabled.txt'
$enabledCount = 0

if (Test-Path -LiteralPath $enabledFile) {
    foreach ($line in (Get-Content -LiteralPath $enabledFile -Encoding UTF8)) {
        $entry = $line.Trim()
        if (-not $entry -or $entry.StartsWith('#')) { continue }
        $enabledCount++

        $srcDir  = Join-Path $vendorRoot ($entry -replace '/', '\')
        $skillMd = Join-Path $srcDir 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillMd)) {
            Add-Finding 'vendor' $entry 'FAIL' 'enabled but no SKILL.md at that path'
            continue
        }

        $fm = Read-FrontMatterFile $skillMd
        $linkName = Split-Path $srcDir -Leaf
        if ($fm.Meta.ContainsKey('name') -and $fm.Meta['name']) { $linkName = $fm.Meta['name'] }
        $expected[$linkName] = $true

        $info = Get-LinkInfo (Join-Path $skillsDest $linkName)
        if ($null -eq $info)          { Add-Finding 'vendor' $linkName 'MISSING' 'enabled but not linked -- run sync.ps1' }
        elseif (-not $info.IsLink)    { Add-Finding 'vendor' $linkName 'CONFLICT' 'real directory in ~/.codex/skills' }
        elseif (-not (Test-SamePath $info.Target $srcDir)) { Add-Finding 'vendor' $linkName 'DRIFT' ("points at '{0}'" -f $info.Target) }
    }
    Add-Finding 'vendor' 'enabled.txt' 'OK' ("{0} skills enabled" -f $enabledCount)
}

# orphans: links in ~/.codex/skills pointing into this repo but no longer backed by a source
foreach ($dest in (Get-ChildItem -Path $skillsDest -Directory -Force -ErrorAction SilentlyContinue)) {
    if ($dest.Name -eq '.system' -or $expected.ContainsKey($dest.Name)) { continue }
    $info = Get-LinkInfo $dest.FullName
    if ($null -eq $info -or -not $info.IsLink -or -not $info.Target) { continue }
    if ($info.Target.ToLower().StartsWith($vendorRoot.ToLower())) {
        Add-Finding 'vendor' $dest.Name 'STALE' 'linked but not in enabled.txt -- run sync.ps1 -Force'
    } elseif ($info.Target.ToLower().StartsWith($root.ToLower())) {
        Add-Finding 'skills' $dest.Name 'ORPHAN' ("junction to '{0}' which no longer exists here" -f $info.Target)
    }
}

# --- global AGENTS.md --------------------------------------------------------------------------

$srcHash  = Get-HashOrNull (Join-Path $root 'global\AGENTS.md')
$destHash = Get-HashOrNull (Join-Path $codexHome 'AGENTS.md')

if ($null -eq $srcHash)         { Add-Finding 'global' 'AGENTS.md' 'FAIL'    'global/AGENTS.md is missing from the repo' }
elseif ($null -eq $destHash)    { Add-Finding 'global' 'AGENTS.md' 'MISSING' 'not copied to ~/.codex -- run sync.ps1' }
elseif ($srcHash -eq $destHash) { Add-Finding 'global' 'AGENTS.md' 'OK'      'in sync' }
else                            { Add-Finding 'global' 'AGENTS.md' 'DRIFT'   '~/.codex copy differs -- run sync.ps1' }

# --- loops -------------------------------------------------------------------------------------

foreach ($loop in (Get-ChildItem -Path (Join-Path $root 'loops') -Filter '*.loop.md' -ErrorAction SilentlyContinue)) {
    $fm   = Read-FrontMatterFile $loop.FullName
    $name = $loop.Name -replace '\.loop\.md$', ''
    $cwd  = $null
    if ($fm.Meta.ContainsKey('cwd')) { $cwd = $fm.Meta['cwd'] }

    if (-not $fm.Body)                                    { Add-Finding 'loops' $name 'FAIL' 'empty prompt body' }
    elseif (-not $fm.Meta.ContainsKey('exit_when'))       { Add-Finding 'loops' $name 'WARN' 'no exit_when -- loop will run to its budget' }
    elseif ($cwd -and -not (Test-Path -LiteralPath $cwd)) { Add-Finding 'loops' $name 'FAIL' "cwd does not exist: $cwd" }
    else                                                  { Add-Finding 'loops' $name 'OK' "cwd=$cwd" }
}

# --- report ------------------------------------------------------------------------------------

$findings | Format-Table -AutoSize

$bad = @($findings | Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'WARN' })
if ($bad.Count -gt 0) {
    Write-Warning ("{0} item(s) need attention." -f $bad.Count)
    exit 1
}
Write-Host "All checks passed." -ForegroundColor Green
exit 0
