<#
.SYNOPSIS
Runs a codex-os loop definition headlessly against `codex exec`, pass by pass, until it reports
done, reports blocked, or hits its iteration budget.

.DESCRIPTION
Reads loops/<name>.loop.md (see loops/_schema.md). Pass 1 starts a session; later passes resume the
specific session ID emitted by that first pass so context carries. Every pass returns JSON matching
schemas/loop-status.schema.json; the runner stops on status = done or blocked.

Output goes to logs/<loop>/<timestamp>/: iter-N.json per pass, plus run.log.

Exit codes: 0 done, 2 budget exhausted, 3 blocked, 1 runner error.

.EXAMPLE
powershell -NoProfile -File scripts\loop.ps1 -Loop repo-health -DryRun

.EXAMPLE
powershell -NoProfile -File scripts\loop.ps1 -Loop repo-health -MaxIterations 3
#>
[CmdletBinding()]
param(
    # Loop name (file basename without .loop.md), or a path to a .loop.md file.
    [Parameter(Mandatory)][string]$Loop,
    # Override max_iterations from the loop file.
    [int]$MaxIterations = 0,
    # Override interval_seconds from the loop file.
    [int]$IntervalSeconds = -1,
    # Print the commands that would run, then exit.
    [switch]$DryRun
)

. "$PSScriptRoot\_common.ps1"
$ErrorActionPreference = 'Stop'

$root   = Get-OsRoot
$schema = Join-Path $root 'scripts\schemas\loop-status.schema.json'

# --- resolve the loop definition ---------------------------------------------------------------

if (Test-Path -LiteralPath $Loop -PathType Leaf) {
    $loopFile = (Resolve-Path $Loop).Path
} else {
    $loopFile = Join-Path $root ('loops\' + ($Loop -replace '\.loop\.md$', '') + '.loop.md')
}
if (-not (Test-Path -LiteralPath $loopFile)) {
    Write-Error "Loop definition not found: $loopFile"
    exit 1
}

$parsed = Read-FrontMatterFile $loopFile
$meta   = $parsed.Meta
$prompt = $parsed.Body

$loopName = Get-MetaValue $meta 'name' ([IO.Path]::GetFileNameWithoutExtension($loopFile) -replace '\.loop$', '')
$cwd      = Get-MetaValue $meta 'cwd' $root
$sandbox  = Get-MetaValue $meta 'sandbox' 'workspace-write'
$model    = Get-MetaValue $meta 'model' $null
$profileName = Get-MetaValue $meta 'profile' $null
$exitWhen = Get-MetaValue $meta 'exit_when' '(not stated)'

$maxIter = [int](Get-MetaValue $meta 'max_iterations' 5)
if ($MaxIterations -gt 0) { $maxIter = $MaxIterations }

$interval = [int](Get-MetaValue $meta 'interval_seconds' 0)
if ($IntervalSeconds -ge 0) { $interval = $IntervalSeconds }

if (-not $prompt) { Write-Error "Loop '$loopName' has an empty prompt body."; exit 1 }
if (-not (Test-Path -LiteralPath $cwd)) { Write-Error "Loop '$loopName' cwd does not exist: $cwd"; exit 1 }
if ($sandbox -notin @('read-only', 'workspace-write', 'danger-full-access')) {
    Write-Error "Loop '$loopName' has invalid sandbox '$sandbox'."; exit 1
}

$codex = Get-CodexExe

# --- run directory -----------------------------------------------------------------------------

$stamp  = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$runDir = Join-Path $root ('logs\' + $loopName + '\' + $stamp)
if (-not $DryRun) { New-Item -ItemType Directory -Path $runDir -Force | Out-Null }
$runLog = Join-Path $runDir 'run.log'
$sessionFile = Join-Path $runDir 'session-id.txt'

function Write-Log {
    param([string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message
    Write-Host $line
    if (-not $DryRun) { Add-Content -LiteralPath $runLog -Value $line -Encoding UTF8 }
}

$contract = @"

---
Loop control (mandatory):
- Exit condition for this loop: $exitWhen
- Do ONE increment of work this pass, then run the check that proves progress.
- Reply with ONLY a JSON object matching the provided output schema.
- status=done only if the exit condition verifiably holds -- you must have run the check this pass.
- status=blocked if you need a decision, credential, or fix outside this loop, or if the same
  failure repeated with no new information. Do not retry a command that failed the same way twice.
- Otherwise status=continue, and put the single next increment in next_action.
"@

Write-Log "loop=$loopName cwd=$cwd sandbox=$sandbox max=$maxIter interval=${interval}s"
Write-Log "exit_when: $exitWhen"

$finalStatus = 'continue'
$threadId = $null

for ($i = 1; $i -le $maxIter; $i++) {

    $iterFile = Join-Path $runDir ('iter-{0}.json' -f $i)

    $cmdArgs = New-Object System.Collections.ArrayList
    [void]$cmdArgs.Add('exec')
    if ($i -gt 1) { [void]$cmdArgs.AddRange(@('resume', $threadId)) }
    [void]$cmdArgs.AddRange(@('-C', $cwd, '-s', $sandbox, '--skip-git-repo-check'))
    [void]$cmdArgs.AddRange(@('--output-schema', $schema, '-o', $iterFile))
    if ($i -eq 1) { [void]$cmdArgs.Add('--json') }
    if ($model)   { [void]$cmdArgs.AddRange(@('-m', $model)) }
    if ($profileName) { [void]$cmdArgs.AddRange(@('-p', $profileName)) }

    if ($i -eq 1) {
        $passPrompt = $prompt + $contract
    } else {
        $passPrompt = "Continue the loop. Pass $i of $maxIter." + $contract
    }
    [void]$cmdArgs.Add($passPrompt)

    if ($DryRun) {
        Write-Host "`n--- pass $i ---" -ForegroundColor Yellow
        Write-Host ('"{0}" {1} "<prompt>"' -f $codex, (($cmdArgs | Select-Object -SkipLast 1) -join ' '))
        if ($i -eq 1) { $threadId = '<session-id from pass 1>' }
        continue
    }

    Write-Log "pass $i/$maxIter -- running"
    $outFile = Join-Path $runDir ("pass-$i.out")
    $errFile = Join-Path $runDir ("pass-$i.err")

    # Never merge a native command's stderr into the pipeline (2>&1): PS 5.1 wraps each line in an
    # ErrorRecord, which $ErrorActionPreference='Stop' turns into a terminating error even on exit 0.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $codex @cmdArgs 1> $outFile 2> $errFile
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prevEap

    if ($code -ne 0) { Write-Log "pass $i -- codex exited $code" }

    if ($i -eq 1) {
        foreach ($line in (Get-Content -LiteralPath $outFile -Encoding UTF8 -ErrorAction SilentlyContinue)) {
            try {
                $event = $line | ConvertFrom-Json
                if ($event.type -eq 'thread.started' -and $event.thread_id) {
                    $threadId = $event.thread_id
                    break
                }
            } catch {}
        }
        if (-not $threadId) {
            Write-Log 'pass 1 -- no session ID in Codex JSON output; cannot safely resume.'
            $finalStatus = 'blocked'
            break
        }
        Set-Content -LiteralPath $sessionFile -Value $threadId -Encoding UTF8
        Write-Log "pass 1 -- session=$threadId"
    }

    $status = 'continue'; $summary = ''; $next = ''
    if (Test-Path -LiteralPath $iterFile) {
        $raw = (Get-Content -LiteralPath $iterFile -Raw -Encoding UTF8).Trim()
        try {
            $obj = $raw | ConvertFrom-Json
            $status  = $obj.status
            $summary = $obj.summary
            $next    = $obj.next_action
        } catch {
            Write-Log "pass $i -- could not parse status JSON; treating as blocked. Raw: $raw"
            $status = 'blocked'; $summary = 'unparseable model output'
        }
    } else {
        Write-Log "pass $i -- no status file written; treating as blocked."
        $status = 'blocked'; $summary = "codex produced no output (exit $code)"
    }

    Write-Log "pass $i -- status=$status :: $summary"
    if ($next) { Write-Log "pass $i -- next: $next" }
    $finalStatus = $status

    if ($status -eq 'done')    { break }
    if ($status -eq 'blocked') { break }
    if ($i -lt $maxIter -and $interval -gt 0) {
        Write-Log "sleeping ${interval}s"
        Start-Sleep -Seconds $interval
    }
}

if ($DryRun) { Write-Host "`nDry run -- nothing was executed." -ForegroundColor Yellow; exit 0 }

switch ($finalStatus) {
    'done'    { Write-Log "loop finished: DONE";    Write-Host "`nlogs: $runDir" -ForegroundColor Green;  exit 0 }
    'blocked' { Write-Log "loop finished: BLOCKED"; Write-Host "`nlogs: $runDir" -ForegroundColor Red;    exit 3 }
    default   { Write-Log "loop finished: BUDGET EXHAUSTED after $maxIter passes"
                Write-Host "`nlogs: $runDir" -ForegroundColor Yellow; exit 2 }
}
