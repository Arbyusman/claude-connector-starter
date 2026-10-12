#!/usr/bin/env bash
#
# Verify that markitdown-mcp runs and that its convert_to_markdown tool works,
# using the MCP Inspector CLI (@modelcontextprotocol/inspector).
#
# Exits 0 only when every check passes, 1 otherwise.
#
# Usage:
#   ./verify-markitdown.sh
#   ./verify-markitdown.sh --uri https://example.com
#   ./verify-markitdown.sh --server "docker run --rm -i markitdown-mcp:latest"

set -uo pipefail

URI=""
SERVER_OVERRIDE=""
FAILURES=0

while [ $# -gt 0 ]; do
  case "$1" in
    --uri)    URI="$2"; shift 2 ;;
    --server) SERVER_OVERRIDE="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

step() { printf '\n==> %s\n' "$1"; }
ok()   { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
info() { printf '        %s\n' "$1"; }

printf 'markitdown-mcp verification (MCP Inspector CLI)\n'

# ------------------------------------------------------------ resolve the server
step "Resolving the server"

SERVER=()

if [ -n "$SERVER_OVERRIDE" ]; then
  # shellcheck disable=SC2206
  SERVER=($SERVER_OVERRIDE)
  info "using --server: $SERVER_OVERRIDE"
elif command -v markitdown-mcp >/dev/null 2>&1; then
  SERVER=("$(command -v markitdown-mcp)")
  ok "found markitdown-mcp at ${SERVER[0]}"
else
  for launcher in py python3 python; do
    if ! command -v "$launcher" >/dev/null 2>&1; then continue; fi
    if "$launcher" -c "import markitdown_mcp" >/dev/null 2>&1; then
      SERVER=("$launcher" -m markitdown_mcp)
      ok "module available via: ${SERVER[*]}"
      break
    fi
  done
fi

if [ ${#SERVER[@]} -eq 0 ]; then
  fail "markitdown-mcp is not installed or not on PATH"
  info "Install it with:  pip install --upgrade markitdown-mcp"
  info "Docker alternative: build markitdown-mcp:latest and use mcp/markitdown-docker.json"
  exit 1
fi

if ! command -v npx >/dev/null 2>&1; then
  fail "npx not found; the MCP Inspector runs through npx (needs Node.js)"
  exit 1
fi

TMP_OUT="$(mktemp)"
TMP_ERR="$(mktemp)"
cleanup() { rm -f "$TMP_OUT" "$TMP_ERR"; }
trap cleanup EXIT

# Runs one inspector request. Sets INSPECT_CODE and leaves stdout in TMP_OUT.
invoke_inspector() {
  npx -y @modelcontextprotocol/inspector --cli "${SERVER[@]}" \
    --method "$1" "${@:2}" --format json >"$TMP_OUT" 2>"$TMP_ERR"
  INSPECT_CODE=$?
}

# ------------------------------------------------------------------ tools/list
step "tools/list"

invoke_inspector tools/list

if [ "$INSPECT_CODE" -ne 0 ]; then
  fail "inspector exited $INSPECT_CODE for tools/list"
  sed 's/^/        /' "$TMP_ERR" | tail -5
else
  if grep -q '"name"[[:space:]]*:[[:space:]]*"convert_to_markdown"' "$TMP_OUT"; then
    ok "server exposes convert_to_markdown"
  else
    fail "convert_to_markdown missing from tools/list"
    head -c 800 "$TMP_OUT" | sed 's/^/        /'
  fi
fi

# ------------------------------------------------ tools/call convert_to_markdown
step "tools/call convert_to_markdown"

MARKER="MARKITDOWN_VERIFY_OK"
SAMPLE_DIR="$(mktemp -d)"
trap 'cleanup; rm -rf "$SAMPLE_DIR"' EXIT

if [ -n "$URI" ]; then
  TARGET="$URI"
  EXPECT_MARKER=0
  info "using supplied URI: $TARGET"
else
  SAMPLE="$SAMPLE_DIR/sample.html"
  printf '<html><body><h1>MarkItDown check</h1><p>%s</p></body></html>' "$MARKER" >"$SAMPLE"
  TARGET="file://$SAMPLE"
  EXPECT_MARKER=1
  info "sample file: $SAMPLE"
fi

invoke_inspector tools/call --tool-name convert_to_markdown --tool-arg "uri=$TARGET"

if [ "$INSPECT_CODE" -ne 0 ]; then
  fail "tools/call exited $INSPECT_CODE (5 = tool error or tool not found)"
  sed 's/^/        /' "$TMP_ERR" | tail -5
elif [ "$EXPECT_MARKER" -eq 1 ] && ! grep -q "$MARKER" "$TMP_OUT"; then
  fail "conversion returned, but the markdown did not contain $MARKER"
  head -c 800 "$TMP_OUT" | sed 's/^/        /'
elif [ "$EXPECT_MARKER" -eq 0 ] && ! grep -q '"text"[[:space:]]*:[[:space:]]*".' "$TMP_OUT"; then
  fail "conversion returned no text content"
  head -c 800 "$TMP_OUT" | sed 's/^/        /'
else
  ok "converted $TARGET to markdown"
fi

# ---------------------------------------------------------------------- summary
step "Summary"

if [ "$FAILURES" -eq 0 ]; then
  printf '  All checks passed: markitdown-mcp runs and convert_to_markdown works.\n'
  exit 0
fi

printf '  %s check(s) failed.\n' "$FAILURES"
exit 1
