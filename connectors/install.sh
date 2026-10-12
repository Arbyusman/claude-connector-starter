#!/usr/bin/env bash
# Install the connectors bundle: markitdown-mcp, figma-console-mcp,
# HyperFrames skills, and the Humanizer skill, then merge the MCP servers
# into Claude Desktop's config. Non-destructive: existing servers are kept
# and a .bak backup is written.
#
# Usage:
#   ./install.sh
#   FIGMA_ACCESS_TOKEN=figd_xxx ./install.sh
#   SKIP_SKILLS=1 ./install.sh
#   WITH_DOCLING=1 ./install.sh     # also add the Docling OCR server (heavy: pulls PyTorch)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

c_cyan='\033[36m'; c_green='\033[32m'; c_yellow='\033[33m'; c_red='\033[31m'; c_gray='\033[90m'; c_off='\033[0m'
step() { printf "\n${c_cyan}==> %s${c_off}\n" "$1"; }
ok()   { printf "    ${c_green}OK${c_off}  %s\n" "$1"; }
warn() { printf "    ${c_yellow}!!${c_off}  %s\n" "$1"; }
err()  { printf "    ${c_red}XX${c_off}  %s\n" "$1"; }

have() { command -v "$1" >/dev/null 2>&1; }

SKIP_SKILLS="${SKIP_SKILLS:-0}"
SKIP_MARKITDOWN="${SKIP_MARKITDOWN:-0}"
SKIP_FIGMA="${SKIP_FIGMA:-0}"
SKIP_CLAUDE_CONFIG="${SKIP_CLAUDE_CONFIG:-0}"
WITH_DOCLING="${WITH_DOCLING:-0}"

printf "Connectors installer\nBundle: %s\n" "$SCRIPT_DIR"

# ------------------------------------------------------------- prerequisites
step "Checking prerequisites"
have node && ok "node $(node --version)" || warn "node not found (needed for figma-console + skills)"
have npx  && ok "npx found"              || warn "npx not found"
have git  && ok "git $(git --version)"   || warn "git not found - required by the skills CLI"
have uvx  && ok "uvx found"              || printf '    %b\n' "${c_gray}--  uvx not found; Docling falls back to pip (https://docs.astral.sh/uv/)${c_off}"
if have pip;  then ok "pip found";  PY="pip";  elif have pip3; then ok "pip3 found"; PY="pip3";
elif have uv; then ok "uv found"; PY="uv"; else warn "pip/uv not found (needed for markitdown-mcp)"; PY=""; fi

# markitdown/markitdown-mcp/magika stop at Python 3.13 and onnxruntime at 3.14,
# so a newer interpreter cannot resolve markitdown-mcp at all.
PY_TOO_NEW=0
py_ver=""
if [ -n "$PY" ] && [ "$PY" != "uv" ]; then
  py_ver="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)"
  if [ -n "$py_ver" ]; then
    py_major="${py_ver%%.*}"; py_minor="${py_ver##*.}"
    if [ "$py_major" -gt 3 ] || { [ "$py_major" -eq 3 ] && [ "$py_minor" -ge 14 ]; }; then
      PY_TOO_NEW=1
      warn "Python $py_ver is newer than this stack supports (markitdown/markitdown-mcp <= 3.13)"
      warn "pip cannot resolve markitdown-mcp here; install Python 3.12 and pin it: python3.12 -m pip install markitdown-mcp"
    fi
  fi
fi

# ----------------------------------------------------------------- 1. skills
if [ "$SKIP_SKILLS" != "1" ]; then
  step "Installing skills"

  humanizer_dest="$HOME/.claude/skills/humanizer"
  if mkdir -p "$humanizer_dest" && cp "$SCRIPT_DIR/skills/humanizer/SKILL.md" "$SCRIPT_DIR/skills/humanizer/LICENSE" "$humanizer_dest/"; then
    ok "Humanizer copied to $humanizer_dest (works offline)"
  else
    warn "Could not copy Humanizer"
  fi

  if have npx; then
    # -y keeps the CLI non-interactive; --copy avoids symlinks.
    skill_args=(-g -a claude-code -y --copy)

    if npx -y skills add blader/humanizer "${skill_args[@]}"; then
      ok "Humanizer installed via skills CLI"
    else
      warn "skills CLI install for humanizer failed; local copy still in place"
    fi

    # --skill '*' takes the whole repo, so there is no interactive picker.
    if npx -y skills add heygen-com/hyperframes --skill '*' "${skill_args[@]}"; then
      ok "HyperFrames skills installed"
    else
      warn "HyperFrames install failed; run manually: npx -y skills add heygen-com/hyperframes --skill '*' -g -a claude-code -y --copy"
    fi
  else
    warn "npx missing; skipped skills-CLI install (local copy still works)"
  fi
else
  step "Skipping skills"
fi

# --------------------------------------------------------- 2. markitdown-mcp
# The command written into each client config. Stays the bare name when pip's
# scripts dir is already on PATH; otherwise it becomes an absolute path,
# because GUI clients inherit the login PATH and cannot find it by name.
MARKITDOWN_CMD="markitdown-mcp"

if [ "$SKIP_MARKITDOWN" != "1" ]; then
  step "Installing markitdown-mcp"
  if [ "$PY" = "uv" ]; then
    # --system: uv otherwise refuses to install without an active virtualenv.
    uv pip install --system --upgrade markitdown-mcp && ok "markitdown-mcp installed via uv" || warn "uv install failed"
  elif [ "$PY_TOO_NEW" = "1" ]; then
    warn "skipped on Python $py_ver - the dependencies cannot resolve; no files were changed"
  elif [ -n "$PY" ]; then
    if "$PY" install --upgrade markitdown-mcp; then
      ok "markitdown-mcp installed via $PY"
      if have markitdown-mcp; then
        MARKITDOWN_CMD="$(command -v markitdown-mcp)"
        ok "on PATH: $MARKITDOWN_CMD"
      else
        # The wrapper is preferred: it re-finds the server after a Python upgrade
        # or a PATH change, unlike a path baked into the config here. On POSIX it
        # needs no args - it is executable, so command can point straight at it.
        wrapper_src="$SCRIPT_DIR/mcp/markitdown-mcp.sh"
        wrapper_dir="$HOME/.markitdown-mcp"
        wrapper_dst="$wrapper_dir/markitdown-mcp.sh"
        if [ -f "$wrapper_src" ] && mkdir -p "$wrapper_dir" && cp "$wrapper_src" "$wrapper_dst" && chmod +x "$wrapper_dst"; then
          MARKITDOWN_CMD="$wrapper_dst"
          warn "not on PATH; the client configs will run the wrapper at $wrapper_dst"
        else
          scripts_dir="$(python3 -c "import sysconfig; print(sysconfig.get_path('scripts'))" 2>/dev/null || true)"
          if [ -n "$scripts_dir" ] && [ -x "$scripts_dir/markitdown-mcp" ]; then
            MARKITDOWN_CMD="$scripts_dir/markitdown-mcp"
            warn "wrapper unavailable; the client configs will use $MARKITDOWN_CMD"
          else
            warn "not found after install; run ./verify-markitdown.sh to diagnose"
          fi
        fi
      fi
    else
      warn "$PY install failed"
    fi
  else
    warn "No pip/uv; skipped markitdown-mcp"
  fi
else
  step "Skipping markitdown-mcp"
fi

# --------------------------------------------------------------- 2b. docling
if [ "$WITH_DOCLING" = "1" ]; then
  step "Docling MCP (OCR + document images)"
  if have uvx; then
    ok "uvx found; docling-mcp[local] is fetched on first run"
    printf '    %b\n' "${c_gray}--  first conversion downloads PyTorch and OCR models (~2-3 GB); later runs are offline${c_off}"
  elif [ "$PY_TOO_NEW" = "1" ]; then
    warn "skipped on Python $py_ver - docling-mcp[local] supports up to 3.14"
    warn "Install uv instead (it brings its own Python): curl -LsSf https://astral.sh/uv/install.sh | sh"
  elif [ -n "$PY" ]; then
    printf '    %b\n' "${c_gray}--  this pulls PyTorch and OCR models (~2-3 GB)${c_off}"
    if [ "$PY" = "uv" ]; then
      uv pip install --system "docling-mcp[local]" && ok "docling-mcp[local] installed" || warn "docling install failed"
    else
      "$PY" install "docling-mcp[local]" && ok "docling-mcp[local] installed" || warn "docling install failed"
    fi
  else
    warn "Neither uvx nor pip found; install uv first: curl -LsSf https://astral.sh/uv/install.sh | sh"
  fi
else
  step "Skipping Docling (set WITH_DOCLING=1 to add it)"
fi

# ------------------------------------------------------------- 3. figma token
if [ "$SKIP_FIGMA" != "1" ]; then
  step "Figma Console MCP token"
  if [ -z "${FIGMA_ACCESS_TOKEN:-}" ] && [ -f "$SCRIPT_DIR/.env" ]; then
    FIGMA_ACCESS_TOKEN="$(sed -n 's/^[[:space:]]*FIGMA_ACCESS_TOKEN[[:space:]]*=[[:space:]]*//p' "$SCRIPT_DIR/.env" | head -n1)"
  fi
  if [ -z "${FIGMA_ACCESS_TOKEN:-}" ]; then
    printf "    ${c_gray}Create a token: https://help.figma.com/hc/en-us/articles/8085703771159-Manage-personal-access-tokens${c_off}\n"
    printf "    Paste your Figma token (or Enter to skip): "
    read -r FIGMA_ACCESS_TOKEN || true
  fi
  if [ -n "${FIGMA_ACCESS_TOKEN:-}" ]; then
    ok "Figma token captured"
  else
    FIGMA_ACCESS_TOKEN="figd_YOUR_TOKEN_HERE"
    warn "No token provided; config contains the placeholder."
  fi
else
  step "Skipping Figma"
  FIGMA_ACCESS_TOKEN="figd_YOUR_TOKEN_HERE"
fi

# ----------------------------------------------- 4. merge Claude Desktop config
if [ "$SKIP_CLAUDE_CONFIG" != "1" ]; then
  step "Writing MCP client configs (Claude Desktop + Cursor)"

  case "$(uname -s)" in
    Darwin) claude_file="$HOME/Library/Application Support/Claude/claude_desktop_config.json" ;;
    Linux)  claude_file="${XDG_CONFIG_HOME:-$HOME/.config}/Claude/claude_desktop_config.json" ;;
    *)      claude_file="$HOME/.config/Claude/claude_desktop_config.json" ;;
  esac
  cursor_file="$HOME/.cursor/mcp.json"

  if have python3; then
    for target in "$claude_file" "$cursor_file"; do
      mkdir -p "$(dirname "$target")"
      if [ -f "$target" ]; then
        cp "$target" "$target.bak" && ok "Backup written: $target.bak"
      fi
      CFG="$target" TOKEN="$FIGMA_ACCESS_TOKEN" MD_CMD="$MARKITDOWN_CMD" WITH_DOCLING="$WITH_DOCLING" python3 - <<'PY'
import json, os
path = os.environ["CFG"]; token = os.environ["TOKEN"]
try:
    with open(path, "r", encoding="utf-8") as f:
        cfg = json.load(f)
except FileNotFoundError:
    cfg = {}
except json.JSONDecodeError as e:
    raise SystemExit(f"Existing config is not valid JSON: {e}\nFix it, then re-run. Nothing was changed.")
cfg.setdefault("mcpServers", {})
cfg["mcpServers"]["markitdown"] = {"command": os.environ["MD_CMD"]}
cfg["mcpServers"]["figma-console"] = {
    "command": "npx",
    "args": ["-y", "figma-console-mcp@latest"],
    "env": {"FIGMA_ACCESS_TOKEN": token, "ENABLE_MCP_APPS": "true"},
}
if os.environ.get("WITH_DOCLING") == "1":
    # Local Docling: OCR for scans, tables and figure captions as Markdown.
    # KEEP_IMAGES=false with placeholder export is the token saving - the
    # document's images never reach the model as images.
    cfg["mcpServers"]["docling"] = {
        "command": "uvx",
        "args": [
            "--from",
            "docling-mcp[local]",
            "docling-mcp-server",
            "--transport",
            "stdio",
        ],
        "env": {
            "DOCLING_MCP_CONVERSION_MODE": "local",
            "DOCLING_MCP_KEEP_IMAGES": "false",
            "DOCLING_MCP_IMAGE_EXPORT_MODE": "placeholder",
            "DOCLING_MCP_DO_OCR": "true",
            "DOCLING_MCP_DO_TABLE_STRUCTURE": "true",
            "DOCLING_MCP_DO_PICTURE_DESCRIPTION": "false",
        },
    }
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PY
      ok "Updated $target"
    done
    printf "    ${c_gray}Note: Claude Code uses 'claude mcp add' (see mcp/claude-code.md).${c_off}\n"
  else
    warn "python3 not found; cannot merge automatically."
    warn "Copy connectors/claude_desktop_config.json into $claude_file by hand."
  fi
else
  step "Skipping Claude config"
fi

# -------------------------------------------------------------------- summary
step "Done"
cat <<EOF
Next steps:
  1. Restart Claude Desktop.
  2. Figma: open Figma Desktop, then
       Plugins -> Development -> Import plugin from manifest...
       and select ~/.figma-console-mcp/plugin/manifest.json
     (that file appears after the server runs once).
  3. Verify markitdown before wiring it up:  ./verify-markitdown.sh
  4. Skills: /humanizer and /hyperframes
EOF
