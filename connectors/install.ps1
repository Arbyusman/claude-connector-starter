#Requires -Version 5.1
<#
.SYNOPSIS
  Install the connectors bundle: markitdown-mcp, figma-console-mcp,
  HyperFrames skills, and the Humanizer skill; then merge the MCP servers
  into Claude Desktop's config.

.DESCRIPTION
  Idempotent and non-destructive: existing Claude Desktop servers are kept,
  and a .bak backup is written before any change.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install.ps1 -FigmaToken figd_xxx
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install.ps1 -SkipSkills
#>
[CmdletBinding()]
param(
    [string]$FigmaToken = "",
    [switch]$SkipSkills,
    [switch]$SkipMarkitdown,
    [switch]$SkipFigma,
    [switch]$SkipClaudeConfig,
    # Adds the Docling MCP server (OCR for scans, tables and figure text).
    # Heavy: the local extra downloads PyTorch and OCR models (~2-3 GB).
    [switch]$WithDocling
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Step { param([string]$Text) Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Text) Write-Host "    OK  $Text" -ForegroundColor Green }
function Write-Warn2{ param([string]$Text) Write-Host "    !!  $Text" -ForegroundColor Yellow }
function Write-Err2 { param([string]$Text) Write-Host "    XX  $Text" -ForegroundColor Red }
function Write-Info2{ param([string]$Text) Write-Host "    --  $Text" -ForegroundColor DarkGray }

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-Npx {
    param([string[]]$NpxArgs)
    # -y avoids the "install this package?" prompt so the script can run unattended.
    $all = @("-y") + $NpxArgs
    & npx @all
    return $LASTEXITCODE
}

function Invoke-Cmd {
    # Runs $Cmd[0] with $Cmd[1..] then $Extra, returning the exit code.
    # A failing tool (pip, for one) writes to stderr; with 2>&1 that arrives as an
    # ErrorRecord, and $ErrorActionPreference = "Stop" would turn it into a
    # terminating error that aborts the whole install. Relaxed for the call only,
    # so a failed install is reported and the config files still get written.
    param([string[]]$Cmd, [string[]]$Extra)
    $exe = $Cmd[0]
    $pre = @()
    if ($Cmd.Length -gt 1) { $pre = $Cmd[1..($Cmd.Length - 1)] }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    # Kept so a failed install can be diagnosed from its own output.
    $script:LastCmdOutput = ""
    try {
        & $exe @pre @Extra 2>&1 | ForEach-Object {
            $line = "$_"
            $script:LastCmdOutput += $line + "`n"
            Write-Host "      $line" -ForegroundColor DarkGray
        }
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
}

Write-Host "Connectors installer" -ForegroundColor White
Write-Host "Bundle: $ScriptDir"

# ---------------------------------------------------------------- prerequisites
Write-Step "Checking prerequisites"
$hasNode = Test-Command "node"
$hasNpx  = Test-Command "npx"

if ($hasNode) { Write-Ok ("node "  + (& node --version)) } else { Write-Warn2 "node not found (needed for figma-console + skills)" }
if ($hasNpx)  { Write-Ok "npx found" } else { Write-Warn2 "npx not found" }

# git: the skills CLI clones skill repos with it, and Git for Windows also
# provides the bash the agent runs terminal commands in.
$hasGit = Test-Command "git"
if ($hasGit) { Write-Ok ("git " + (& git --version)) }
else { Write-Warn2 "git not found - required by the skills CLI, and Git for Windows provides bash. Install: winget install --id Git.Git -e --source winget" }

# uv/uvx: runs docling-mcp without a permanent install.
$hasUvx = Test-Command "uvx"
if ($hasUvx) { Write-Ok "uvx found" }
else { Write-Info2 "uvx not found; Docling falls back to a pip install (install uv: winget install --id astral-sh.uv -e --source winget)" }

# The Python install manager keeps its runtimes under %LOCALAPPDATA%\Python and
# installs a pinned version with `py install <version>`, which is not the same as
# the winget package. It also explains a version selector resolving elsewhere.
$hasPyManager = Test-Path (Join-Path $env:LOCALAPPDATA "Python\bin")
if ($hasPyManager) {
    Write-Ok "Python install manager detected (add a version with: py install 3.12)"
    $pyInstallHint = "py install 3.12"
} else {
    $pyInstallHint = "winget install --id Python.Python.3.12 -e --source winget"
}

# Find a working Python. Newest is not best here: markitdown, magika and
# markitdown-mcp all declare support up to Python 3.13, and onnxruntime (pulled
# in through magika) stops at 3.14 - so on a newer interpreter pip backtracks
# through every version and then fails. Pinned interpreters are listed first, and
# the ranking below decides which one is actually used.
# `uv pip --version` is not a valid uv invocation, so pip/uv are probed with their
# own `--version` while interpreters are asked for sys.version_info instead.
$pipCandidates = @(
    @("py", "-3.13", "-m", "pip"),
    @("py", "-3.12", "-m", "pip"),
    @("py", "-3.11", "-m", "pip"),
    @("py", "-3", "-m", "pip"),
    @("python", "-m", "pip"),
    @("python3", "-m", "pip"),
    @("pip"),
    @("uv", "pip")
)

# A selector is not a guarantee: `py -3.13` has been observed resolving to
# whatever interpreter the launcher prefers (3.15 here). So every candidate is
# asked for its real version and the answers are ranked, instead of taking the
# first that starts:
#   1. a known-supported interpreter (3.13 / 3.12 / 3.11, in that order)
#   2. a known-too-new one, which the guard below refuses to install on
#   3. an unknown one (bare pip / uv), which is attempted last
$pipCmd = $null
$pyVersion = ""
$tooNewCmd = $null
$tooNewVersion = ""
$unknownCmd = $null

foreach ($cand in $pipCandidates) {
    if ($pipCmd) { break }
    if (-not (Test-Command $cand[0])) { continue }
    try {
        if ($cand[0] -in @("pip", "uv")) {
            # A bare `pip` may be a shim for whichever runtime the Python
            # install manager prefers (seen: 3.15 while 3.12 was installed) and
            # `pip --version` does not tell you. If a likely selector behind it
            # asks for a supported interpreter, prefer that explicit form so the
            # install does not silently happen on the shim's runtime instead.
            $probe = ""
            & $cand[0] --version *> $null
            if ($LASTEXITCODE -eq 0 -and $cand[0] -eq "pip" -and (Test-Command "py")) {
                foreach ($v in @("3.13", "3.12", "3.11")) {
                    $probeArgs = @("-$v", "-c", "import sys; print('%d.%d' % sys.version_info[:2])")
                    $found = (& py @probeArgs 2>$null | Select-Object -First 1)
                    if ($found -match "^$v$") {
                        # Trust the version text, not $LASTEXITCODE: the py shim is
                        # an App Execution Alias stub that PowerShell reports as
                        # crashed (LE=-1610612730) even on a working Python.
                        $cand = @("py", "-$v", "-m", "pip")
                        $probe = $found
                        break
                    }
                }
            }
        } else {
            # Ask the interpreter itself for its version. `py --version` has
            # written to stderr across launcher releases, which left the version
            # undetected and let an unsupported interpreter through unchecked.
            $selector = @()
            if ($cand.Length -gt 1 -and $cand[1] -like "-3*") { $selector = @($cand[1]) }
            $probeArgs = $selector + @("-c", "import sys; print('%d.%d' % sys.version_info[:2])")
            $probe = (& $cand[0] @probeArgs 2>$null | Select-Object -First 1)
        }

        # Re-test a candidate that probed successfully but whose exit code looks
        # like the App Execution Alias stub's fake crash (LE<0). The py shim is
        # such a stub: PowerShell sees status 0xC0000135 (-1610612730) even when
        # the real launcher succeeds, so $LASTEXITCODE after it cannot be
        # trusted. Inside cmd.exe the child's real exit code reaches PowerShell.
        if ($probe -match '(\d+)\.(\d+)' -and $LASTEXITCODE -lt 0 -and $cand[0] -in @("py", "python", "python3") -and (Test-Command "cmd")) {
            $selector = @()
            if ($cand.Length -gt 1 -and $cand[1] -like "-3*") { $selector = @($cand[1]) }
            # The `python` shims are not a real launcher chain; route to `py`.
            $innerCmd = if ($cand[0] -eq "py") { $cand[0] } else { "py" }
            $argsJoined = (($selector + @("-c", "import sys; print('%d.%d' % sys.version_info[:2])")) | ForEach-Object { '"' + $_ + '"' }) -join " "
            $cmdLine = "$innerCmd $argsJoined"
            cmd /c "$cmdLine 2>nul"
            if ($LASTEXITCODE -ne 0) { continue }
            # Keep $probe from the direct call, which already held the version.
        }

        if ($LASTEXITCODE -ne 0) { continue }

        if (-not ($probe -match '(\d+)\.(\d+)')) {
            if (-not $unknownCmd) { $unknownCmd = $cand }
            continue
        }

        $candVersion = "$($Matches[1]).$($Matches[2])"
        $parts = $candVersion.Split('.')
        $candTooNew = ([int]$parts[0] -gt 3 -or ([int]$parts[0] -eq 3 -and [int]$parts[1] -ge 14))

        if ($candTooNew) {
            # Remembered, not used, so the search keeps going for a supported one.
            if (-not $tooNewCmd) { $tooNewCmd = $cand; $tooNewVersion = $candVersion }
            continue
        }

        $pipCmd = $cand
        $pyVersion = $candVersion
    } catch { }
}

if (-not $pipCmd -and $tooNewCmd) {
    $pipCmd = $tooNewCmd
    $pyVersion = $tooNewVersion
} elseif (-not $pipCmd -and $unknownCmd) {
    # Version unknown, so nothing can be ruled out: attempt it and let the
    # install's own output decide.
    $pipCmd = $unknownCmd
}

if ($pipCmd) {
    $via = $pipCmd -join " "
    if ($pyVersion) { $via = "$via (Python $pyVersion)" }
    Write-Ok "python/pip via: $via"
} else {
    Write-Warn2 "No working Python (py/python/pip/uv) found (needed for markitdown-mcp)"
    Write-Warn2 "Install Python from https://www.python.org/downloads/ (check 'Add to PATH'), or winget install Python.Python.3.12"
}

# True when the selected interpreter is too new for the MarkItDown stack's pins.
$pyTooNew = $false
if ($pyVersion) {
    $parts = $pyVersion.Split('.')
    if ([int]$parts[0] -gt 3 -or ([int]$parts[0] -eq 3 -and [int]$parts[1] -ge 14)) { $pyTooNew = $true }
}
if ($pyTooNew) {
    Write-Warn2 "Python $pyVersion is newer than this stack supports (markitdown/markitdown-mcp <= 3.13, onnxruntime <= 3.14)"
    Write-Warn2 "pip cannot resolve markitdown-mcp on it. Add a supported interpreter:"
    Write-Warn2 "  $pyInstallHint"
    Write-Warn2 "  py -3.12 -m pip install markitdown-mcp"
}

# ------------------------------------------------------------------- 1. skills
if (-not $SkipSkills) {
    Write-Step "Installing skills"

    # Humanizer: canonical CLI install, plus a local offline copy.
    $humanizerDest = Join-Path $env:USERPROFILE ".claude\skills\humanizer"
    try {
        New-Item -ItemType Directory -Force -Path $humanizerDest | Out-Null
        Copy-Item -Path (Join-Path $ScriptDir "skills\humanizer\SKILL.md") -Destination $humanizerDest -Force
        Copy-Item -Path (Join-Path $ScriptDir "skills\humanizer\LICENSE")   -Destination $humanizerDest -Force
        Write-Ok "Humanizer copied to $humanizerDest (works offline)"
    } catch {
        Write-Warn2 "Could not copy Humanizer: $($_.Exception.Message)"
    }

    # -y keeps the CLI non-interactive (every prompt fails without a TTY) and
    # --copy avoids symlinks, which need Developer Mode on Windows.
    $skillArgs = @("-g", "-a", "claude-code", "-y", "--copy")

    if (-not $hasGit) {
        Write-Warn2 "git missing: the skills CLI clones from GitHub, so these installs may fail"
    }

    if ($hasNpx) {
        if ((Invoke-Npx (@("skills", "add", "blader/humanizer") + $skillArgs)) -eq 0) {
            Write-Ok "Humanizer installed via skills CLI"
        } else {
            Write-Warn2 "skills CLI install for humanizer failed; the local copy above still works"
        }
    } else {
        Write-Warn2 "npx missing; skipped skills-CLI install (local copy still works)"
    }

    if ($hasNpx) {
        # --skill '*' takes the whole repo, so there is no interactive picker.
        if ((Invoke-Npx (@("skills", "add", "heygen-com/hyperframes", "--skill", "*") + $skillArgs)) -eq 0) {
            Write-Ok "HyperFrames skills installed"
        } else {
            Write-Warn2 "HyperFrames skills install failed; run manually: npx -y skills add heygen-com/hyperframes --skill '*' -g -a claude-code -y --copy"
        }
    }
} else {
    Write-Step "Skipping skills (-SkipSkills)"
}

# ------------------------------------------------------------- 2. markitdown-mcp
# The command written into each client config. Stays the bare name when pip's
# Scripts dir is already on PATH; otherwise it becomes an absolute path, because
# Claude Desktop and Cursor inherit the user PATH and cannot find it by name.
$MarkitdownCommand = "markitdown-mcp"
$MarkitdownArgs = @()

if (-not $SkipMarkitdown) {
    Write-Step "Installing markitdown-mcp"
    if ($pipCmd -and $pyTooNew) {
        # Not attempted: the resolver demonstrably cannot succeed here, and the
        # backtracking run takes minutes. Printed instead of silently skipped.
        Write-Warn2 "skipped on Python $pyVersion - the dependencies cannot resolve; no files were changed"
        Write-Warn2 "Run it on a supported interpreter, or use Docker (mcp/markitdown-docker.json):"
        Write-Warn2 "  py -3.12 -m pip install markitdown-mcp"
    } elseif ($pipCmd) {
        $code = Invoke-Cmd $pipCmd @("install", "--upgrade", "markitdown-mcp")
        if ($code -eq 0) {
            Write-Ok "markitdown-mcp installed"
            $found = Get-Command "markitdown-mcp" -ErrorAction SilentlyContinue
            if ($found) {
                Write-Ok "on PATH: $($found.Source)"
            } else {
                # Not on PATH, which is normal after a per-user pip install. The
                # wrapper is preferred: it re-finds the server after a Python
                # upgrade or a PATH change, unlike a path baked in here.
                $wrapperSrc = Join-Path $ScriptDir "mcp\markitdown-mcp.cmd"
                $wrapperDir = Join-Path $env:USERPROFILE ".markitdown-mcp"
                $wrapperDst = Join-Path $wrapperDir "markitdown-mcp.cmd"
                if (Test-Path $wrapperSrc) {
                    try {
                        New-Item -ItemType Directory -Force -Path $wrapperDir | Out-Null
                        Copy-Item $wrapperSrc $wrapperDst -Force
                        $MarkitdownCommand = "cmd"
                        $MarkitdownArgs = @("/c", $wrapperDst)
                        Write-Warn2 "not on PATH; the client configs will run the wrapper at $wrapperDst"
                    } catch {
                        Write-Warn2 "could not write the wrapper: $($_.Exception.Message)"
                    }
                }

                # Fallback when the bundled wrapper is missing: pin the absolute
                # path of the installed script.
                if ($MarkitdownCommand -eq "markitdown-mcp" -and $pipCmd[0] -in @("py", "python", "python3")) {
                    # Only the interpreter selector: passing the candidate through
                    # would run `py -3 -m pip -c ...`, and pip has no -c.
                    $selector = @()
                    if ($pipCmd.Length -gt 1 -and $pipCmd[1] -like "-3*") { $selector = @($pipCmd[1]) }
                    $scriptsDir = (& $pipCmd[0] @selector -c "import sysconfig; print(sysconfig.get_path('scripts'))" 2>$null | Select-Object -First 1)
                    if ($scriptsDir) {
                        $exePath = Join-Path $scriptsDir.Trim() "markitdown-mcp.exe"
                        if (Test-Path $exePath) {
                            $MarkitdownCommand = $exePath
                            Write-Warn2 "wrapper unavailable; the client configs will use $exePath"
                        }
                    }
                }

                if ($MarkitdownCommand -eq "markitdown-mcp") {
                    Write-Warn2 "could not locate markitdown-mcp after install; run .\verify-markitdown.ps1 to diagnose"
                }
            }
        }
        else {
            Write-Warn2 "install failed; see the pip output above"
            if ($script:LastCmdOutput -match "conflicting dependencies") {
                # Version-independent backstop: pip's resolver cannot report which
                # constraint failed, so name the usual cause and the way out.
                Write-Warn2 "pip could not resolve this stack - usually an unsupported Python version"
                Write-Warn2 "Pin a supported interpreter (3.12 or 3.13):"
                Write-Warn2 "  py -3.12 -m pip install markitdown-mcp"
            } else {
                Write-Warn2 "or use the Docker variant in mcp/markitdown-docker.json"
            }
        }
    } else {
        Write-Warn2 "No Python; skipped markitdown-mcp. Install Python, then re-run this script."
        Write-Warn2 "  $pyInstallHint"
    }
} else {
    Write-Step "Skipping markitdown-mcp (-SkipMarkitdown)"
}

# --------------------------------------------------------------- 2b. docling
# Without uvx the config must not name "docling-mcp-server" bare: a per-user pip
# install drops the script in the interpreter's Scripts dir, which GUI clients do
# not get on their PATH (seen: spawn docling-mcp-server ENOENT). Same treatment
# as markitdown above - resolve the real .exe and write its absolute path.
$DoclingCommand = $null
$DoclingArgs = @("--transport", "stdio")

if ($WithDocling) {
    Write-Step "Docling MCP (OCR + document images)"
    if ($hasUvx) {
        Write-Ok "uvx found; docling-mcp[local] will be fetched on first run (no install step)"
        Write-Info2 "first conversion downloads PyTorch and OCR models (~2-3 GB); later runs are offline"
    } elseif ($pipCmd -and $pyTooNew) {
        # docling-mcp supports up to Python 3.14, and PyTorch wheels lag further.
        # uvx is the way out: it manages its own interpreter.
        Write-Warn2 "skipped on Python $pyVersion - docling-mcp[local] supports up to 3.14"
        Write-Warn2 "Install uv (it brings its own Python) and re-run: winget install --id astral-sh.uv -e --source winget"
    } elseif ($pipCmd) {
        Write-Info2 "this pulls PyTorch and OCR models (~2-3 GB)"
        Write-Info2 "if pip ends in 'conflicting dependencies', fall back to:"
        Write-Info2 "  $($pipCmd -join ' ') install docling-mcp"
        Write-Info2 "  $($pipCmd -join ' ') install 'docling[standard]'"
        $code = Invoke-Cmd $pipCmd @("install", "--upgrade", "docling-mcp[local]")
        if ($code -ne 0) {
            # docling-mcp[local] pins docling-core[chunking], whose tree-sitter
            # range cannot resolve under this pip; the non-extra docling-mcp can.
            Write-Warn2 "docling-mcp[local] did not resolve; retrying without the [local] extra"
            $code = Invoke-Cmd $pipCmd @("install", "--upgrade", "docling-mcp")
            if ($code -eq 0) {
                # Conversion tools work without the extra, but OCR needs the full
                # docling runtime; install it separately and allow it to fail on
                # its own build step.
                Write-Info2 "adding the conversion runtime: 'docling[standard]' (OCR models download on first use)"
                $doclingCode = Invoke-Cmd $pipCmd @("install", "--upgrade", "docling[standard]")
                if ($doclingCode -eq 0) { Write-Ok "docling[standard] installed" }
                else { Write-Warn2 "docling[standard] failed; conversion still works, OCR will not - see the pip output above" }
            }
        }
        if ($code -eq 0) {
            Write-Ok "docling-mcp installed"
            $found = Get-Command "docling-mcp-server" -ErrorAction SilentlyContinue
            if ($found) {
                Write-Ok "on PATH: $($found.Source)"
                $DoclingCommand = $found.Source
            } else {
                # Same pin-the-absolute-path fallback as markitdown.
                if ($pipCmd[0] -in @("py", "python", "python3")) {
                    $selector = @()
                    if ($pipCmd.Length -gt 1 -and $pipCmd[1] -like "-3*") { $selector = @($pipCmd[1]) }
                    $scriptsDir = (& $pipCmd[0] @selector -c "import sysconfig; print(sysconfig.get_path('scripts'))" 2>$null | Select-Object -First 1)
                    if ($scriptsDir) {
                        $exePath = Join-Path $scriptsDir.Trim() "docling-mcp-server.exe"
                        if (Test-Path $exePath) {
                            $DoclingCommand = $exePath
                            Write-Warn2 "not on PATH; the client configs will use $exePath"
                        }
                    }
                }
                if (-not $DoclingCommand) {
                    Write-Warn2 "could not locate docling-mcp-server after install; run .\verify-docling.ps1 to diagnose"
                }
            }
        }
        else { Write-Warn2 "docling install failed; install uv instead: winget install --id astral-sh.uv -e --source winget" }
    } else {
        Write-Warn2 "Neither uvx nor Python found; install uv first: winget install --id astral-sh.uv -e --source winget"
    }
} else {
    Write-Step "Skipping Docling (-WithDocling not set)"
}

# ---------------------------------------------------------------- 3. figma token
if (-not $SkipFigma) {
    Write-Step "Figma Console MCP token"

    if (-not $FigmaToken) {
        $envFile = Join-Path $ScriptDir ".env"
        if (Test-Path $envFile) {
            $m = Select-String -Path $envFile -Pattern '^\s*FIGMA_ACCESS_TOKEN\s*=\s*(.+)\s*$' | Select-Object -First 1
            if ($m) { $FigmaToken = $m.Matches[0].Groups[1].Value.Trim() }
        }
    }
    if (-not $FigmaToken -and $env:FIGMA_ACCESS_TOKEN) { $FigmaToken = $env:FIGMA_ACCESS_TOKEN }

    if (-not $FigmaToken) {
        Write-Host "    Create a token at https://help.figma.com/hc/en-us/articles/8085703771159-Manage-personal-access-tokens" -ForegroundColor DarkGray
        Write-Host "    Scopes: File content (R), File versions (R), Variables (R), Comments (R/W). It starts with figd_" -ForegroundColor DarkGray
        $secure = Read-Host "    Paste your Figma token (or press Enter to skip)"
        $FigmaToken = $secure
    }

    if ($FigmaToken -and $FigmaToken -ne "figd_YOUR_TOKEN_HERE") {
        $preview = $FigmaToken.Substring(0, [Math]::Min(5, $FigmaToken.Length))
        Write-Ok "Figma token captured ($preview...)"
    } else {
        $FigmaToken = "figd_YOUR_TOKEN_HERE"
        Write-Warn2 "No token provided; config will contain the placeholder. Edit it before use."
    }
} else {
    Write-Step "Skipping Figma (-SkipFigma)"
    $FigmaToken = "figd_YOUR_TOKEN_HERE"
}

# --------------------------------------------- 4. write MCP client config files
function Write-McpConfig {
    param([string]$Path, [bool]$EnableFigma = $true, [bool]$EnableDocling = $false)

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    if (Test-Path $Path) {
        Copy-Item $Path "$Path.bak" -Force
        Write-Ok "Backup written: $Path.bak"
        try {
            $config = Get-Content $Path -Raw | ConvertFrom-Json
        } catch {
            Write-Err2 "$Path is not valid JSON: $($_.Exception.Message)"
            Write-Err2 "Fix it, then re-run. This file was not changed."
            return
        }
    } else {
        $config = [pscustomobject]@{}
    }

    if (-not ($config.PSObject.Properties.Name -contains "mcpServers")) {
        $config | Add-Member -NotePropertyName "mcpServers" -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    # args is only present when the command needs them (the cmd /c wrapper form).
    $markitdownEntry = [pscustomobject]@{ command = $MarkitdownCommand }
    if ($MarkitdownArgs.Count -gt 0) {
        $markitdownEntry | Add-Member -NotePropertyName "args" -NotePropertyValue $MarkitdownArgs -Force
    }
    $config.mcpServers | Add-Member -NotePropertyName "markitdown" -NotePropertyValue $markitdownEntry -Force

    if ($EnableDocling) {
        # Local Docling: OCR for scans, plus tables and figure captions as
        # Markdown. KEEP_IMAGES=false with the placeholder export mode is the
        # token saving - the document's images never reach the model as images.
        $doclingEnv = [pscustomobject]@{
            DOCLING_MCP_CONVERSION_MODE        = "local"
            DOCLING_MCP_KEEP_IMAGES            = "false"
            DOCLING_MCP_IMAGE_EXPORT_MODE      = "placeholder"
            DOCLING_MCP_DO_OCR                 = "true"
            DOCLING_MCP_DO_TABLE_STRUCTURE     = "true"
            DOCLING_MCP_DO_PICTURE_DESCRIPTION = "false"
        }
        if ($hasUvx) {
            $docling = [pscustomobject]@{
                command = "uvx"
                args    = @("--from", "docling-mcp[local]", "docling-mcp-server", "--transport", "stdio")
                env     = $doclingEnv
            }
        } elseif ($DoclingCommand) {
            # Resolved .exe from a pip install; its Scripts dir is not on the
            # PATH GUI clients inherit, so the bare name spawned ENOENT there.
            $docling = [pscustomobject]@{
                command = $DoclingCommand
                args    = $DoclingArgs
                env     = $doclingEnv
            }
        } else {
            # pip install "docling-mcp[local]" puts this console script on PATH.
            $docling = [pscustomobject]@{
                command = "docling-mcp-server"
                args    = @("--transport", "stdio")
                env     = $doclingEnv
            }
        }
        $config.mcpServers | Add-Member -NotePropertyName "docling" -NotePropertyValue $docling -Force
    }

    if ($EnableFigma) {
        $figmaEnv = [pscustomobject]@{
            FIGMA_ACCESS_TOKEN = $FigmaToken
            ENABLE_MCP_APPS    = "true"
        }
        $figma = [pscustomobject]@{
            command = "npx"
            args    = @("-y", "figma-console-mcp@latest")
            env     = $figmaEnv
        }
        $config.mcpServers | Add-Member -NotePropertyName "figma-console" -NotePropertyValue $figma -Force
    }

    $json = $config | ConvertTo-Json -Depth 100
    # UTF8 without BOM, which some clients reject.
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Ok "Updated $Path"
}

# Claude Desktop ships two ways on Windows: the classic installer, which puts its
# config in %APPDATA%\Claude, and the MSIX/Store package, whose %APPDATA% is
# redirected into the package container. Writing only the classic path is why a
# config can look correct on disk and never reach a Store-installed app, so every
# location that exists gets the merge (existing keys, like the app's own
# preferences, are preserved).
$claudeFiles = @()
if (Test-Path (Join-Path $env:APPDATA "Claude")) {
    $claudeFiles += (Join-Path $env:APPDATA "Claude\claude_desktop_config.json")
}
$packagesRoot = Join-Path $env:LOCALAPPDATA "Packages"
if (Test-Path $packagesRoot) {
    Get-ChildItem -Path $packagesRoot -Directory -Filter "Claude*" -ErrorAction SilentlyContinue | ForEach-Object {
        $pkgClaude = Join-Path $_.FullName "LocalCache\Roaming\Claude"
        if (Test-Path $pkgClaude) {
            $claudeFiles += (Join-Path $pkgClaude "claude_desktop_config.json")
        }
    }
}
if ($claudeFiles.Count -eq 0) {
    # No Claude Desktop found: write the classic path so the file is ready for it.
    $claudeFiles = @(Join-Path $env:APPDATA "Claude\claude_desktop_config.json")
}

$cursorFile = Join-Path $env:USERPROFILE ".cursor\mcp.json"

if (-not $SkipClaudeConfig) {
    Write-Step "Writing MCP client configs"
    foreach ($claudeFile in $claudeFiles) {
        Write-McpConfig -Path $claudeFile -EnableFigma $true -EnableDocling ([bool]$WithDocling)
    }
    Write-McpConfig -Path $cursorFile -EnableFigma $true -EnableDocling ([bool]$WithDocling)
    Write-Host "    Note: Claude Code uses 'claude mcp add' (see mcp/claude-code.md); not written automatically." -ForegroundColor DarkGray
} else {
    Write-Step "Skipping MCP client configs (-SkipClaudeConfig)"
}

# --------------------------------------------------------------------- summary
Write-Step "Done"
Write-Host @"
Next steps:
  1. Restart Claude Desktop.
  2. Figma: open Figma Desktop, then run
       Plugins -> Development -> Import plugin from manifest...
       and select %USERPROFILE%\.figma-console-mcp\plugin\manifest.json
     (that file appears after the server runs once).
  3. Verify markitdown before wiring it up:
       powershell -ExecutionPolicy Bypass -File .\verify-markitdown.ps1
     then test in the client with: convert this PDF to markdown
  4. Skills: /humanizer and /hyperframes

Files written by this bundle:
  Claude Desktop : $($claudeFiles -join "`n                   ")
  Cursor         : $cursorFile
  Humanizer      : $humanizerDest
  markitdown cmd : $MarkitdownCommand $($MarkitdownArgs -join ' ')
  docling cmd    : $(if ($DoclingCommand) { $DoclingCommand } elseif (-not $WithDocling) { '(skipped)' } else { '(not resolved - see warnings above)' })
"@ -ForegroundColor Gray
