#Requires -Version 5.1
<#
.SYNOPSIS
  Verify that the Docling MCP server starts, and (optionally) that it converts a
  document, using the MCP Inspector CLI.

.DESCRIPTION
  The Docling server is started over stdio and its tools are listed through
  @modelcontextprotocol/inspector. Two checks run by default:

    1. the server command resolves (uvx, or the docling-mcp-server script)
    2. tools/list exposes convert_document_into_docling_document

  With -Convert a third check generates a small HTML file, converts it, and
  requires a document_key back. That is the slow one: the first conversion of a
  local install downloads PyTorch and the OCR models (~2-3 GB), so it is opt-in.

  Exits 0 only when every check run passes, 1 otherwise.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\verify-docling.ps1

.EXAMPLE
  # also run a real conversion (first run downloads the models)
  powershell -ExecutionPolicy Bypass -File .\verify-docling.ps1 -Convert

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\verify-docling.ps1 -Convert -Source C:\docs\scan.pdf
#>
[CmdletBinding()]
param(
    # Run a real conversion instead of stopping after tools/list.
    [switch]$Convert,

    # Convert this file instead of a generated HTML sample.
    [string]$Source
)

$script:Failures = 0

function Write-Step { param([string]$T) Write-Host "`n==> $T" -ForegroundColor Cyan }
function Write-Ok   { param([string]$T) Write-Host "  PASS  $T" -ForegroundColor Green }
function Write-Fail { param([string]$T) Write-Host "  FAIL  $T" -ForegroundColor Red; $script:Failures++ }
function Write-Info { param([string]$T) Write-Host "        $T" -ForegroundColor DarkGray }

Write-Host "Docling MCP verification (MCP Inspector CLI)" -ForegroundColor White

# ------------------------------------------------------------ resolve the server
Write-Step "Resolving the server"

$server = @()

if (Get-Command uvx -ErrorAction SilentlyContinue) {
    $server = @(
        "uvx", "--from", "docling-mcp[local]",
        "docling-mcp-server", "--transport", "stdio"
    )
    Write-Ok "uvx found; using docling-mcp[local]"
} elseif (Get-Command docling-mcp-server -ErrorAction SilentlyContinue) {
    $server = @((Get-Command docling-mcp-server).Source, "--transport", "stdio")
    Write-Ok "using docling-mcp-server from pip"
}

if ($server.Count -eq 0) {
    Write-Fail "neither uvx nor docling-mcp-server found"
    Write-Info "Install uv:   winget install --id astral-sh.uv -e --source winget"
    Write-Info "or with pip:  py -3 -m pip install `"docling-mcp[local]`""
    exit 1
}

if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
    Write-Fail "npx not found; the MCP Inspector runs through npx (needs Node.js)"
    exit 1
}

function Invoke-Inspector {
    param([string]$Method, [string[]]$MethodArgs = @())

    # The Inspector has its own --transport, and this server needs --transport
    # stdio, so all Inspector flags go before "--" and the server command after
    # it. Otherwise the Inspector would swallow the server's flag.
    $npxArgs = @("-y", "@modelcontextprotocol/inspector", "--cli",
                 "--method", $Method) + $MethodArgs + @("--format", "json", "--") + $server

    $stdout = & npx @npxArgs 2>$null
    $code = $LASTEXITCODE
    return [pscustomobject]@{ ExitCode = $code; Text = ($stdout | Out-String) }
}

# ------------------------------------------------------------------ tools/list
Write-Step "tools/list"

$list = Invoke-Inspector -Method "tools/list"

if ($list.ExitCode -ne 0) {
    Write-Fail "inspector exited $($list.ExitCode) for tools/list"
    Write-Info "command: npx -y @modelcontextprotocol/inspector --cli --method tools/list -- $($server -join ' ')"
    Write-Info ($list.Text.Trim())
    Write-Info "If the Inspector rejects the '--' form, connect the same server in the browser UI instead."
} else {
    $names = @()
    try {
        $parsed = $list.Text | ConvertFrom-Json
        $names = @($parsed.result.tools | ForEach-Object { $_.name })
    } catch {
        Write-Info "could not parse JSON from the inspector output"
    }

    if ($names -contains "convert_document_into_docling_document") {
        Write-Ok "server exposes convert_document_into_docling_document"
        Write-Info ("tools: " + (($names | Sort-Object) -join ", "))
    } else {
        Write-Fail "convert_document_into_docling_document missing from tools/list (saw: $($names -join ', '))"
        Write-Info ($list.Text.Trim())
    }
}

if (-not $Convert) {
    Write-Info "conversion skipped; re-run with -Convert (first local run downloads the models)"
} else {
    # -------------------------------------------------------------- tools/call
    Write-Step "tools/call convert_document_into_docling_document"

    $tmp = Join-Path $env:TEMP ("docling-verify-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null

    try {
        if ($Source) {
            $target = (Resolve-Path $Source).Path
            Write-Info "using supplied source: $target"
        } else {
            $target = Join-Path $tmp "sample.html"
            "<html><body><h1>Docling check</h1><p>DOCLING_VERIFY_OK</p></body></html>" |
                Set-Content -Path $target -Encoding UTF8
            Write-Info "sample file: $target"
        }

        $call = Invoke-Inspector -Method "tools/call" `
            -MethodArgs @("--tool-name", "convert_document_into_docling_document", "--tool-arg", "source=$target")

        if ($call.ExitCode -ne 0) {
            Write-Fail "tools/call exited $($call.ExitCode) (5 = tool error or tool not found)"
            Write-Info ($call.Text.Trim())
        } elseif ($call.Text -notmatch "document_key") {
            Write-Fail "the conversion returned no document_key"
            Write-Info ($call.Text.Trim())
        } else {
            Write-Ok "converted $target and cached it under a document_key"
            Write-Info "next: export_docling_document_to_markdown with that document_key"
        }
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------- summary
Write-Step "Summary"

if ($script:Failures -eq 0) {
    Write-Host "  All checks passed." -ForegroundColor Green
    exit 0
}

Write-Host "  $script:Failures check(s) failed." -ForegroundColor Red
exit 1
