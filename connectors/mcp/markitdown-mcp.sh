#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# markitdown-mcp launcher for macOS and Linux.
#
# GUI-spawned MCP clients inherit the login PATH, which often misses the pip
# user-base bin directory that holds markitdown-mcp. This wrapper finds the
# server itself, so the client config survives Python upgrades and PATH changes.
#
# Called through exec, so stdin/stdout stay attached to the client - required
# for the stdio transport.
#
# install.sh copies it to ~/.markitdown-mcp/ and wires that path up.
# ---------------------------------------------------------------------------

set -u

# 1. The console script, wherever it sits on PATH.
if command -v markitdown-mcp >/dev/null 2>&1; then
  exec markitdown-mcp "$@"
fi

# 2. The module through a pinned interpreter: markitdown supports up to
#    Python 3.13, and an unsupported interpreter cannot import it at all.
for candidate in python3.13 python3.12 python3.11; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c "import markitdown_mcp" >/dev/null 2>&1; then
    exec "$candidate" -m markitdown_mcp "$@"
  fi
done

# 3. Whatever python3 / python resolves to.
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c "import markitdown_mcp" >/dev/null 2>&1; then
    exec "$candidate" -m markitdown_mcp "$@"
  fi
done

printf 'markitdown-mcp is not installed.\nInstall it with: python3.12 -m pip install markitdown-mcp\n' >&2
exit 1
