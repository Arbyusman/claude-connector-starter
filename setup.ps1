#Requires -Version 5.1
<#
.SYNOPSIS
  One-command setup for D:\arby\ai: installs every dependency Claude Code needs
  for this workspace (Git, Node.js, Python 3.12, uv, FFmpeg), the MCP servers
  (markitdown, docling, figma-console), and the skills (HyperFrames, Humanizer).

.DESCRIPTION
  Idempotent: anything already installed is skipped, so it is safe to re-run.
  Run it with setup.cmd (double-click) or:
    powershell -ExecutionPolicy Bypass -File .\setup.ps1

.EXAMPLE
  .\setup.ps1 -FigmaToken figd_xxx      # also stores the Figma token
.EXAMPLE
  .\setup.ps1 -SkipDocling               # skip the ~2-3 GB OCR stack
.EXAMPLE
  .\setup.ps1 -WithDesktop               # also configure Claude Desktop + Cursor
#>
[CmdletBinding()]
param(
    [string]$FigmaToken = "",
    [switch]$SkipDocling,
    [switch]$SkipHyperframes,
    [switch]$WithDesktop
)

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:Failures = @()

function Step { param($t) Write-Host "`n==> $t" -ForegroundColor Cyan }
function Ok   { param($t) Write-Host "    OK  $t" -ForegroundColor Green }
function Warn { param($t) Write-Host "    !!  $t" -ForegroundColor Yellow; $script:Failures += $t }
function Info { param($t) Write-Host "    --  $t" -ForegroundColor DarkGray }

function Has { param($name) [bool](Get-Command $name -ErrorAction SilentlyContinue) }

function Refresh-Path {
    # winget installs update the registry PATH, not this process's PATH.
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user    = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

function Winget-Install {
    param([string]$Id, [string]$Label, [scriptblock]$Present)
    if (& $Present) { Ok "$Label already installed"; return }
    if (-not (Has "winget")) { Warn "$Label missing and winget is unavailable - install it manually"; return }
    Info "installing $Label ($Id) via winget..."
    winget install --id $Id -e --source winget --accept-package-agreements --accept-source-agreements --silent | Out-Host
    Refresh-Path
    if (& $Present) { Ok "$Label installed" } else { Warn "$Label install did not complete (a new terminal may be needed)" }
}

function Has-Py312 {
    if (-not (Has "py")) { return $false }
    & py -3.12 -c "import sys" 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Pip312 {
    param([string[]]$PipArgs)
    & py -3.12 -m pip @PipArgs --disable-pip-version-check | Out-Host
    return $LASTEXITCODE
}

function Py312-Has { param($module) & py -3.12 -c "import $module" 2>$null; return ($LASTEXITCODE -eq 0) }

# ------------------------------------------------------------------ 1. tools
Step "1/6  System tools (winget)"
Winget-Install "Git.Git"                 "Git"         { Has "git" }
Winget-Install "OpenJS.NodeJS.LTS"       "Node.js"     { Has "npx" }
Winget-Install "Python.Python.3.12"      "Python 3.12" { Has-Py312 }
Winget-Install "astral-sh.uv"            "uv"          { Has "uv" }
if (-not $SkipHyperframes) {
    # HyperFrames renders MP4 through FFmpeg.
    Winget-Install "Gyan.FFmpeg"         "FFmpeg"      { Has "ffmpeg" }
}

# ------------------------------------------------------------ 2. markitdown
Step "2/6  markitdown-mcp (Python 3.12)"
if (-not (Has-Py312)) { Warn "Python 3.12 not available - skipping Python packages (re-run in a new terminal)" }
elseif (Py312-Has "markitdown_mcp") { Ok "markitdown-mcp already installed" }
else {
    if ((Pip312 @("install", "--upgrade", "markitdown-mcp", "markitdown[all]")) -eq 0) { Ok "markitdown-mcp installed" }
    else { Warn "markitdown-mcp install failed - see pip output above" }
}

# --------------------------------------------------------------- 3. docling
Step "3/6  docling-mcp (OCR)"
if ($SkipDocling) { Info "skipped (-SkipDocling)" }
elseif (-not (Has-Py312)) { Warn "Python 3.12 not available - skipping docling" }
elseif ((Py312-Has "docling_mcp") -and (Py312-Has "docling")) { Ok "docling-mcp already installed" }
else {
    Info "downloads PyTorch + OCR models (~2-3 GB), this takes a while..."
    $code = Pip312 @("install", "--upgrade", "docling-mcp[local]")
    if ($code -ne 0) {
        Info "[local] extra did not resolve; installing docling-mcp + docling[standard] separately"
        $code = Pip312 @("install", "--upgrade", "docling-mcp")
        if ($code -eq 0) { $code = Pip312 @("install", "--upgrade", "docling[standard]") }
    }
    if ($code -eq 0) { Ok "docling-mcp installed" } else { Warn "docling install failed - see pip output above" }
}

# ---------------------------------------------------------------- 4. skills
Step "4/6  Claude Code skills"
$skillsDir = Join-Path $env:USERPROFILE ".claude\skills"
New-Item -ItemType Directory -Force -Path $skillsDir | Out-Null

# Humanizer: vendored copy, works offline.
$humanSrc = Join-Path $Root "connectors\skills\humanizer"
$humanDst = Join-Path $skillsDir "humanizer"
if (Test-Path (Join-Path $humanDst "SKILL.md")) { Ok "humanizer already installed" }
elseif (Test-Path $humanSrc) { Copy-Item -Recurse -Force $humanSrc $humanDst; Ok "humanizer installed" }
else { Warn "connectors\skills\humanizer not found" }

if ($SkipHyperframes) { Info "HyperFrames skipped (-SkipHyperframes)" }
elseif (-not (Has "npx")) { Warn "npx missing - cannot install HyperFrames (re-run in a new terminal)" }
else {
    if (Test-Path (Join-Path $skillsDir "hyperframes\SKILL.md")) {
        Info "HyperFrames skills present; updating..."
        & npx -y hyperframes@latest skills update | Out-Host
    } else {
        Info "installing HyperFrames skills..."
        & npx -y skills add heygen-com/hyperframes --global --agent claude-code --yes | Out-Host
    }
    if (Test-Path (Join-Path $skillsDir "hyperframes\SKILL.md")) { Ok "HyperFrames skills ready" }
    else { Warn "HyperFrames skills not found after install - run: npx skills add heygen-com/hyperframes --global --agent claude-code" }

    # Warm the npx cache so the first render does not stall on a download.
    Info "caching the HyperFrames CLI..."
    & npx -y hyperframes@latest --version | Out-Host
    if ($LASTEXITCODE -eq 0) { Ok "HyperFrames CLI ready (npx hyperframes)" } else { Warn "HyperFrames CLI did not start" }
}

# ----------------------------------------------------------------- 5. figma
Step "5/6  Figma token"
if (-not $FigmaToken) { $FigmaToken = [Environment]::GetEnvironmentVariable("FIGMA_ACCESS_TOKEN", "User") }
if (-not $FigmaToken) {
    $envFile = Join-Path $Root "connectors\.env"
    if (Test-Path $envFile) {
        $line = Get-Content $envFile | Where-Object { $_ -match '^FIGMA_ACCESS_TOKEN=(figd_.+)$' -and $_ -notmatch 'YOUR_TOKEN' }
        if ($line) { $FigmaToken = ($line -split '=', 2)[1].Trim() }
    }
}
if (-not $FigmaToken) {
    $FigmaToken = Read-Host "    Figma token (figd_..., Enter to skip)"
}
if ($FigmaToken) {
    [Environment]::SetEnvironmentVariable("FIGMA_ACCESS_TOKEN", $FigmaToken, "User")
    $env:FIGMA_ACCESS_TOKEN = $FigmaToken
    Ok "FIGMA_ACCESS_TOKEN saved to your user environment"
} else {
    Info "skipped - figma-console will not connect until FIGMA_ACCESS_TOKEN is set"
}

if ($WithDesktop) {
    Info "configuring Claude Desktop + Cursor via connectors\install.ps1..."
    $desktopArgs = @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $Root "connectors\install.ps1"), "-SkipSkills")
    if ($FigmaToken) { $desktopArgs += @("-FigmaToken", $FigmaToken) }
    if (-not $SkipDocling) { $desktopArgs += "-WithDocling" }
    & powershell @desktopArgs
}

# ---------------------------------------------------------------- 6. verify
Step "6/6  Verify MCP servers"
$init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"setup","version":"1"}}}'
function Test-Server {
    param([string]$Label, [string[]]$Cmd)
    $out = $init | & $Cmd[0] $Cmd[1..($Cmd.Length - 1)] 2>$null | Select-Object -First 1
    if ("$out" -match '"serverInfo"') { Ok "$Label responds" } else { Warn "$Label did not respond" }
}
if (Has-Py312) {
    Test-Server "markitdown" @("py", "-3.12", "-m", "markitdown_mcp")
    if (-not $SkipDocling) {
        Test-Server "docling" @("py", "-3.12", "-c", "from docling_mcp.servers.mcp_server import app; app()", "--transport", "stdio")
    }
}

Write-Host ""
if ($script:Failures.Count -eq 0) {
    Write-Host "All done. Open Claude Code in $Root - the servers in .mcp.json load automatically." -ForegroundColor Green
} else {
    Write-Host "Finished with $($script:Failures.Count) warning(s):" -ForegroundColor Yellow
    $script:Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    Write-Host "Fix them (often: open a new terminal) and re-run setup.cmd." -ForegroundColor Yellow
}
