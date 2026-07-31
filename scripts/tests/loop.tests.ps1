$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = (Resolve-Path (Join-Path $here '..\..')).Path
$loop = Join-Path $root 'scripts\loop.ps1'

Describe 'loop.ps1 dry run' {
    It 'resumes the session started by pass one instead of the global last session' {
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $loop -Loop repo-health -DryRun 2>&1

        $text = $output -join "`n"
        $text | Should Match '--json'
        $text | Should Match 'exec resume <session-id from pass 1>'
        $text | Should Not Match 'resume --last'
    }
}

Describe 'sync.ps1 safety contract' {
    It 'requires Force before overwriting a changed global AGENTS.md copy' {
        $sync = Get-Content -LiteralPath (Join-Path $root 'scripts\sync.ps1') -Raw -Encoding UTF8

        $sync.Contains('if (-not $Force) {') | Should Be $true
        $sync | Should Match "Add-Result 'AGENTS\.md' 'DRIFT'"
    }
}

Describe 'validate.ps1' {
    It 'accepts the current repository structure' {
        $validate = Join-Path $root 'scripts\validate.ps1'
        & powershell -NoProfile -ExecutionPolicy Bypass -File $validate
        $LASTEXITCODE | Should Be 0
    }
}
