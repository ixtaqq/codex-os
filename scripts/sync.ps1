<#
.SYNOPSIS
Wires codex-os into ~/.codex: a junction per skill, plus the global AGENTS.md.

.DESCRIPTION
Idempotent. Junctions are live, so editing a SKILL.md here takes effect in the next thread with no
re-sync. Re-run only after adding a skill folder or editing global/AGENTS.md.

Never deletes a real directory. A real directory sitting where a junction should go is reported and
skipped -- resolve it by hand.

.EXAMPLE
powershell -NoProfile -File scripts\sync.ps1 -DryRun

.EXAMPLE
powershell -NoProfile -File scripts\sync.ps1
#>
[CmdletBinding()]
param(
    # Preview actions without changing anything.
    [switch]$DryRun,
    # Re-point junctions whose target has drifted, unlink stale vendor junctions, or overwrite a
    # modified ~/.codex/AGENTS.md after backing it up.
    [switch]$Force
)

. "$PSScriptRoot\_common.ps1"
$ErrorActionPreference = 'Stop'

$root       = Get-OsRoot
$codexHome  = Get-CodexHome
$skillsSrc  = Join-Path $root 'skills'
$skillsDest = Join-Path $codexHome 'skills'
$results    = New-Object System.Collections.ArrayList

function Add-Result {
    param([string]$Item, [string]$Action, [string]$Detail)
    [void]$results.Add([pscustomobject]@{ Item = $Item; Action = $Action; Detail = $Detail })
}

if (-not (Test-Path $codexHome)) {
    throw "CODEX_HOME not found at '$codexHome'. Is Codex installed for this user?"
}
if (-not (Test-Path $skillsDest)) {
    if ($DryRun) {
        Add-Result 'skills/' 'would create' $skillsDest
    } else {
        New-Item -ItemType Directory -Path $skillsDest -Force | Out-Null
    }
}

# --- skills: one junction per folder -----------------------------------------------------------

foreach ($skill in (Get-ChildItem -Path $skillsSrc -Directory -ErrorAction SilentlyContinue)) {
    if ($skill.Name -like '.*') { continue }

    $link = Join-Path $skillsDest $skill.Name

    if (-not (Test-Path (Join-Path $skill.FullName 'SKILL.md'))) {
        Add-Result $skill.Name 'skipped' 'no SKILL.md'
        continue
    }

    if (-not (Test-Path -LiteralPath $link)) {
        if ($DryRun) {
            Add-Result $skill.Name 'would link' $link
        } else {
            New-Item -ItemType Junction -Path $link -Value $skill.FullName | Out-Null
            Add-Result $skill.Name 'linked' $link
        }
        continue
    }

    if (Test-IsLink $link) {
        $target = Get-LinkTarget $link
        if ($target -and ($target.TrimEnd('\') -ieq $skill.FullName.TrimEnd('\'))) {
            Add-Result $skill.Name 'ok' 'junction current'
        } elseif ($Force) {
            if ($DryRun) {
                Add-Result $skill.Name 'would re-point' "$target -> $($skill.FullName)"
            } else {
                Remove-Link $link
                New-Item -ItemType Junction -Path $link -Value $skill.FullName | Out-Null
                Add-Result $skill.Name 're-pointed' "was: $target"
            }
        } else {
            Add-Result $skill.Name 'DRIFT' "points at '$target' -- re-run with -Force"
        }
        continue
    }

    Add-Result $skill.Name 'CONFLICT' "real directory exists at '$link' -- move or delete it yourself"
}

# --- vendor skills: enabled entries from vendor/enabled.txt --------------------------------------

$vendorRoot    = Join-Path $root 'vendor'
$enabledFile   = Join-Path $vendorRoot 'enabled.txt'
$vendorWanted  = @{}   # link name -> source folder

if (Test-Path -LiteralPath $enabledFile) {
    foreach ($line in (Get-Content -LiteralPath $enabledFile -Encoding UTF8)) {
        $entry = $line.Trim()
        if (-not $entry -or $entry.StartsWith('#')) { continue }

        $srcDir = Join-Path $vendorRoot ($entry -replace '/', '\')
        if (-not (Test-Path -LiteralPath $srcDir -PathType Container)) {
            Add-Result $entry 'MISSING SRC' 'no such folder under vendor/'
            continue
        }

        $skillMd = Join-Path $srcDir 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillMd)) {
            Add-Result $entry 'skipped' 'no SKILL.md'
            continue
        }

        # The frontmatter name wins over the folder name: several upstream folders disagree with
        # their own SKILL.md, and Codex keys the skill on the declared name.
        $linkName = Get-MetaValue (Read-FrontMatterFile $skillMd).Meta 'name' (Split-Path $srcDir -Leaf)

        if ($vendorWanted.ContainsKey($linkName)) {
            Add-Result $linkName 'COLLISION' "two vendor entries claim this name; '$entry' ignored"
            continue
        }
        $vendorWanted[$linkName] = (Resolve-Path $srcDir).Path
    }
}

foreach ($linkName in ($vendorWanted.Keys | Sort-Object)) {
    $srcDir = $vendorWanted[$linkName]
    $link   = Join-Path $skillsDest $linkName

    if (-not (Test-Path -LiteralPath $link)) {
        if ($DryRun) {
            Add-Result $linkName 'would link' 'vendor'
        } else {
            New-Item -ItemType Junction -Path $link -Value $srcDir | Out-Null
            Add-Result $linkName 'linked' 'vendor'
        }
        continue
    }

    if (Test-IsLink $link) {
        $target = Get-LinkTarget $link
        if ($target -and ($target.TrimEnd('\') -ieq $srcDir.TrimEnd('\'))) {
            Add-Result $linkName 'ok' 'vendor junction current'
        } elseif ($Force) {
            if ($DryRun) {
                Add-Result $linkName 'would re-point' "$target -> $srcDir"
            } else {
                Remove-Link $link
                New-Item -ItemType Junction -Path $link -Value $srcDir | Out-Null
                Add-Result $linkName 're-pointed' "was: $target"
            }
        } else {
            Add-Result $linkName 'DRIFT' "points at '$target' -- re-run with -Force"
        }
    } else {
        Add-Result $linkName 'CONFLICT' "real directory exists at '$link'"
    }
}

# Links into vendor/ that enabled.txt no longer lists. Removing a junction never touches the files
# it points at, but it is still a removal, so it needs -Force.
foreach ($dest in (Get-ChildItem -Path $skillsDest -Directory -Force -ErrorAction SilentlyContinue)) {
    if ($dest.Name -eq '.system' -or $vendorWanted.ContainsKey($dest.Name)) { continue }
    if (-not (Test-IsLink $dest.FullName)) { continue }
    $target = Get-LinkTarget $dest.FullName
    if (-not $target) { continue }
    if (-not $target.ToLower().StartsWith($vendorRoot.ToLower())) { continue }

    if ($Force) {
        if ($DryRun) {
            Add-Result $dest.Name 'would unlink' 'disabled in enabled.txt'
        } else {
            Remove-Link $dest.FullName
            Add-Result $dest.Name 'unlinked' 'disabled in enabled.txt (source folder untouched)'
        }
    } else {
        Add-Result $dest.Name 'STALE' 'no longer in enabled.txt -- re-run with -Force to unlink'
    }
}

# --- global guidance: copied, because a single file cannot be junctioned ------------------------

$agentsSrc  = Join-Path $root 'global\AGENTS.md'
$agentsDest = Join-Path $codexHome 'AGENTS.md'

if (Test-Path $agentsSrc) {
    $srcHash  = Get-FileHashOrNull $agentsSrc
    $destHash = Get-FileHashOrNull $agentsDest

    if ($null -eq $destHash) {
        if ($DryRun) {
            Add-Result 'AGENTS.md' 'would copy' $agentsDest
        } else {
            Copy-Item -LiteralPath $agentsSrc -Destination $agentsDest -Force
            Add-Result 'AGENTS.md' 'copied' $agentsDest
        }
    } elseif ($srcHash -eq $destHash) {
        Add-Result 'AGENTS.md' 'ok' 'in sync'
    } else {
        # Destination differs. It may hold edits made directly in ~/.codex that are not in the repo.
        $backup = "$agentsDest.bak"
        if (-not $Force) {
            Add-Result 'AGENTS.md' 'DRIFT' 'differs from repo -- re-run with -Force to back up and overwrite'
        } elseif ($DryRun) {
            Add-Result 'AGENTS.md' 'would overwrite' "differs from repo (backup -> $backup)"
        } else {
            Copy-Item -LiteralPath $agentsDest -Destination $backup -Force
            Copy-Item -LiteralPath $agentsSrc -Destination $agentsDest -Force
            Add-Result 'AGENTS.md' 'updated' "previous version saved to $backup"
        }
    }
}

# --- report ------------------------------------------------------------------------------------

$results | Format-Table -AutoSize

$problems = @($results | Where-Object { $_.Action -in @('DRIFT', 'CONFLICT', 'MISSING SRC', 'COLLISION', 'STALE') })
if ($problems.Count -gt 0) {
    Write-Warning "$($problems.Count) item(s) need attention -- see the flagged rows above."
    exit 1
}
if ($DryRun) { Write-Host "`nDry run -- nothing was changed." -ForegroundColor Yellow }
else { Write-Host "`nSync complete. Open a new Codex thread to pick up changes." -ForegroundColor Green }
exit 0
