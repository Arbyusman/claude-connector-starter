@echo off
rem ---------------------------------------------------------------------------
rem markitdown-mcp launcher.
rem
rem MCP clients inherit the PATH the app started with, which often does not
rem include the Python "Scripts" directory that holds markitdown-mcp.exe (a
rem per-user pip install puts it under %APPDATA%\Python). This wrapper finds the
rem server itself, so the client config stays valid across Python upgrades and
rem PATH changes.
rem
rem Use it from a client config as:
rem   "command": "cmd",
rem   "args": ["/c", "C:\\Users\\YOU\\.markitdown-mcp\\markitdown-mcp.cmd"]
rem
rem install.ps1 copies it to %USERPROFILE%\.markitdown-mcp\ and wires that path up.
rem ---------------------------------------------------------------------------
setlocal enabledelayedexpansion

rem 1. The console script, wherever it sits on PATH.
set "MD_EXE="
for %%I in (markitdown-mcp.exe) do set "MD_EXE=%%~$PATH:I"
if defined MD_EXE (
    "%MD_EXE%" %*
    exit /b !ERRORLEVEL!
)

rem 2. The module through a pinned interpreter: markitdown supports up to
rem    Python 3.13, and an unsupported interpreter cannot import it at all.
py -3.13 -c "import markitdown_mcp" 1>nul 2>nul
if not errorlevel 1 (
    py -3.13 -m markitdown_mcp %*
    exit /b !ERRORLEVEL!
)

py -3.12 -c "import markitdown_mcp" 1>nul 2>nul
if not errorlevel 1 (
    py -3.12 -m markitdown_mcp %*
    exit /b !ERRORLEVEL!
)

py -3.11 -c "import markitdown_mcp" 1>nul 2>nul
if not errorlevel 1 (
    py -3.11 -m markitdown_mcp %*
    exit /b !ERRORLEVEL!
)

rem 3. Whatever `py -3` resolves to.
py -3 -c "import markitdown_mcp" 1>nul 2>nul
if not errorlevel 1 (
    py -3 -m markitdown_mcp %*
    exit /b !ERRORLEVEL!
)

echo markitdown-mcp is not installed. 1>&2
echo Install it with: py -3.12 -m pip install markitdown-mcp 1>&2
exit /b 1
