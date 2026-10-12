#Requires -Version 5.1
<#
.SYNOPSIS
  Verify that markitdown-mcp runs and that its convert_to_markdown tool works,
  using the MCP Inspector CLI (@modelcontextprotocol/inspector).

.DESCRIPTION
  Runs three checks against the installed markitdown-mcp server:

    1. the server command resolves (markitdown-mcp, or `py -3 -m markitdown_mcp`)
    2. tools/list exposes convert_to_markdown
    3. tools/call convert_to_markdown converts a real local file to markdown

  Exits 0 only when every check passes, 1 otherwise. Run it after install.ps1.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\verify-markitdown.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\verify-markitdown.ps1 -Uri https://example.com

.EXAMPLE
  # For the Docker variant (build it first, see mcp/markitdown-docker.json):
  powershell -ExecutionPolicy Bypass -File .\verify-markitdown.ps1 `
      -ServerCommand "docker run --rm -i markitdown-mcp:latest"
#>
[CmdletBinding()]
param(
    # Optional: verify this URI instead of a generated local sample file.
    [string]$Uri,

    # Optional: override the server command line (e.g. the Docker variant).
    [string]$ServerCommand
)

$script:Failures = 0

function Write-Step { param([string]$T) Write-Host "`n==> $T" -ForegroundColor Cyan }
function Write-Ok   { param([string]$T) Write-Host "  PASS  $T" -ForegroundColor Green }
function Write-Fail { param([string]$T) Write-Host "  FAIL  $T" -ForegroundColor Red; $script:Failures++ }
function Write-Info { param([string]$T) Write-Host "        $T" -ForegroundColor DarkGray }

Write-Host "markitdown-mcp verification (MCP Inspector CLI)" -ForegroundColor White

# ------------------------------------------------------------ resolve the server
Write-Step "Resolving the server"

$server = @()

if ($ServerCommand) {
    $server = $ServerCommand -split '\s+'
    Write-Info "using -ServerCommand: $ServerCommand"
} elseif (Get-Command markitdown-mcp -ErrorAction SilentlyContinue) {
    $server = @((Get-Command markitdown-mcp).Source)
    Write-Ok "found markitdown-mcp at $($server[0])"
} else {
    foreach ($launcher in @(@("py", "-3"), @("python"))) {
        if ($server.Count -gt 0) { break }
        if (-not (Get-Command $launcher[0] -ErrorAction SilentlyContinue)) { continue }
        $pre = @()
        if ($launcher.Length -gt 1) { $pre = $launcher[1..($launcher.Length - 1)] }
        & $launcher[0] @pre -c "import markitdown_mcp" 2>$null
        if ($LASTEXITCODE -eq 0) {
            $server = @($launcher) + @("-m", "markitdown_mcp")
            Write-Ok "module available via: $($server -join ' ')"
        }
    }
}

if ($server.Count -eq 0) {
    Write-Fail "markitdown-mcp is not installed or not on PATH"
    Write-Info "Install it with:  py -3 -m pip install --upgrade markitdown-mcp"
    Write-Info "Docker alternative: build markitdown-mcp:latest and use mcp/markitdown-docker.json"
    exit 1
}

if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
    Write-Fail "npx not found; the MCP Inspector runs through npx (needs Node.js)"
    exit 1
}

function Invoke-Inspector {
    param([string]$Method, [string[]]$MethodArgs = @())

    $npxArgs = @("-y", "@modelcontextprotocol/inspector", "--cli") + $server +
               @("--method", $Method) + $MethodArgs + @("--format", "json")

    # stderr carries npm notices; stdout is the single JSON object we parse.
    $stdout = & npx @npxArgs 2>$null
    $code = $LASTEXITCODE
    return [pscustomobject]@{ ExitCode = $code; Text = ($stdout | Out-String) }
}

# ------------------------------------------------------------------ tools/list
Write-Step "tools/list"

$list = Invoke-Inspector -Method "tools/list"

if ($list.ExitCode -ne 0) {
    Write-Fail "inspector exited $($list.ExitCode) for tools/list"
    Write-Info ($list.Text.Trim())
} else {
    $names = @()
    try {
        $parsed = $list.Text | ConvertFrom-Json
        $names = @($parsed.result.tools | ForEach-Object { $_.name })
    } catch {
        Write-Info "could not parse JSON from the inspector output"
    }

    if ($names -contains "convert_to_markdown") {
        Write-Ok "server exposes convert_to_markdown"
    } else {
        Write-Fail "convert_to_markdown missing from tools/list (saw: $($names -join ', '))"
        Write-Info ($list.Text.Trim())
    }
}

# ------------------------------------------------ tools/call convert_to_markdown
Write-Step "tools/call convert_to_markdown"

$marker = "MARKITDOWN_VERIFY_OK"
$tmp = Join-Path $env:TEMP ("markitdown-verify-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    if ($Uri) {
        $target = $Uri
        $expectMarker = $false
        Write-Info "using supplied URI: $target"
    } else {
        $samplePath = Join-Path $tmp "sample.html"
        "<html><body><h1>MarkItDown check</h1><p>$marker</p></body></html>" |
            Set-Content -Path $samplePath -Encoding UTF8
        $target = ([System.Uri]$samplePath).AbsoluteUri
        $expectMarker = $true
        Write-Info "sample file: $samplePath"
    }

    $call = Invoke-Inspector -Method "tools/call" `
        -MethodArgs @("--tool-name", "convert_to_markdown", "--tool-arg", "uri=$target")

    if ($call.ExitCode -ne 0) {
        Write-Fail "tools/call exited $($call.ExitCode) (5 = tool error or tool not found)"
        Write-Info ($call.Text.Trim())
    } elseif ($expectMarker -and ($call.Text -notmatch [regex]::Escape($marker))) {
        Write-Fail "conversion returned, but the markdown did not contain $marker"
        Write-Info ($call.Text.Trim())
    } elseif (-not $expectMarker -and ($call.Text -notmatch '"text"\s*:\s*".+')) {
        Write-Fail "conversion returned no text content"
        Write-Info ($call.Text.Trim())
    } else {
        Write-Ok "converted $target to markdown"
    }
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------- summary
Write-Step "Summary"

if ($script:Failures -eq 0) {
    Write-Host "  All checks passed: markitdown-mcp runs and convert_to_markdown works." -ForegroundColor Green
    exit 0
}

Write-Host "  $script:Failures check(s) failed." -ForegroundColor Red
exit 1
