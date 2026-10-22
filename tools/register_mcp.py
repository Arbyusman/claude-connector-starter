"""Register this workspace's MCP servers with Claude on this machine.

  Claude Code    ~/.claude.json  -> top-level "mcpServers" (user scope, every project)
  Claude Desktop %APPDATA%/Claude/claude_desktop_config.json -> "mcpServers"

Claude Code entries managed here are (re)written each run. Claude Desktop
entries are only added when missing, so hand-made ones (and their tokens) stay.
A timestamped .bak is written before any file changes.

Usage: py -3.12 tools/register_mcp.py [--skip-docling] [--skip-desktop]
"""

from __future__ import annotations

import json
import os
import shutil
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PY = sys.executable  # absolute path: GUI-launched clients may not have py on PATH

DOCLING_ENV = {
    "DOCLING_MCP_CONVERSION_MODE": "local",
    "DOCLING_MCP_KEEP_IMAGES": "false",
    "DOCLING_MCP_IMAGE_EXPORT_MODE": "placeholder",
    "DOCLING_MCP_DO_OCR": "true",
    "DOCLING_MCP_DO_TABLE_STRUCTURE": "true",
    "DOCLING_MCP_DO_PICTURE_DESCRIPTION": "false",
}


def servers(skip_docling: bool, figma_token: str | None, for_desktop: bool) -> dict:
    s = {
        "markitdown": {"command": PY, "args": ["-m", "markitdown_mcp"]},
        "docimage": {"command": PY, "args": [str(ROOT / "tools" / "docimage_mcp.py")]},
        "figma-console": {
            "command": "npx",
            "args": ["-y", "figma-console-mcp@latest"],
            # Claude Code expands ${VAR}; Claude Desktop needs the literal value.
            "env": {
                "FIGMA_ACCESS_TOKEN": figma_token if for_desktop else "${FIGMA_ACCESS_TOKEN}",
                "ENABLE_MCP_APPS": "true",
            },
        },
    }
    if not skip_docling:
        s["docling"] = {
            "command": PY,
            "args": ["-c", "from docling_mcp.servers.mcp_server import app; app()", "--transport", "stdio"],
            "env": DOCLING_ENV,
        }
    if not for_desktop:
        # Remote OAuth server. Claude Desktop gets Canva from Settings > Connectors instead.
        s["canva"] = {"type": "http", "url": "https://mcp.canva.com/mcp"}
    if for_desktop and not figma_token:
        del s["figma-console"]
    return s


def load(path: Path) -> dict:
    if not path.exists():
        return {}
    text = path.read_text(encoding="utf-8").strip()
    return json.loads(text) if text else {}


def save(path: Path, data: dict) -> None:
    if path.exists():
        backup = path.with_name(f"{path.name}.{time.strftime('%Y%m%d-%H%M%S')}.bak")
        shutil.copy2(path, backup)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def register(path: Path, wanted: dict, overwrite: bool, label: str) -> None:
    data = load(path)
    current = data.setdefault("mcpServers", {})
    changed = []
    for name, cfg in wanted.items():
        if name in current and (not overwrite or current[name] == cfg):
            continue
        current[name] = cfg
        changed.append(name)
    if changed:
        save(path, data)
        print(f"    OK  {label}: added/updated {', '.join(changed)}")
    else:
        print(f"    OK  {label}: already up to date")


def main() -> int:
    skip_docling = "--skip-docling" in sys.argv
    skip_desktop = "--skip-desktop" in sys.argv
    token = os.environ.get("FIGMA_ACCESS_TOKEN") or None

    register(Path.home() / ".claude.json", servers(skip_docling, token, False), True, "Claude Code (user scope)")

    if not skip_desktop:
        appdata = os.environ.get("APPDATA")
        if appdata:
            desktop = Path(appdata) / "Claude" / "claude_desktop_config.json"
            register(desktop, servers(skip_docling, token, True), False, "Claude Desktop")
    return 0


if __name__ == "__main__":
    sys.exit(main())
