"""Register this workspace's MCP servers with Claude on this machine.

Targets (every location that actually exists is written):

  Claude Code       ~/.claude.json -> top-level "mcpServers" (user scope, every project)
                    ~/.claude.json -> projects["<this repo>"].enabledMcpjsonServers
                                      (auto-approves the repo's .mcp.json, so its
                                      connectors appear without a manual prompt)
  Claude Desktop    every claude_desktop_config.json in use, including the
                    Microsoft Store / MSIX build, whose %APPDATA% is redirected to
                    %LOCALAPPDATA%\\Packages\\Claude_*\\LocalCache\\Roaming\\Claude.
                    Writing only %APPDATA% is the classic bug: the file looks
                    correct on disk but the installed app never reads it.

Claude Code entries managed here are (re)written each run. Claude Desktop
entries are only added when missing (an existing placeholder Figma token is
upgraded when a real token is available). A timestamped .bak is written before
any file changes.

NOTE: do not run this while a Claude Code session is open in this repo - Claude
Code rewrites ~/.claude.json on exit and would clobber the changes.

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
    try:
        return json.loads(text) if text else {}
    except json.JSONDecodeError:
        print(f"    !!  {path} is not valid JSON - left untouched")
        return {}


def save(path: Path, data: dict) -> None:
    if path.exists():
        backup = path.with_name(f"{path.name}.{time.strftime('%Y%m%d-%H%M%S')}.bak")
        shutil.copy2(path, backup)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def needs_repair(name: str, existing) -> bool:
    """True for entries that are known-broken in GUI-launched clients.

    A bare "markitdown-mcp" command depends on pip's Scripts dir being on the
    PATH the client inherited; when it is not, the server dies with
    spawn markitdown-mcp ENOENT and the connector silently never appears.
    The absolute `python -m markitdown_mcp` form cannot fail that way.
    Docker/other hand-made variants are left alone.
    """
    if name == "markitdown" and isinstance(existing, dict):
        return existing.get("command") == "markitdown-mcp" and not existing.get("args")
    return False


def register(path: Path, wanted: dict, overwrite: bool, label: str) -> None:
    data = load(path)
    current = data.setdefault("mcpServers", {})
    changed = []
    for name, cfg in wanted.items():
        existing = current.get(name)
        if existing is not None and (not overwrite or existing == cfg):
            # Keep hand-made entries, but upgrade a placeholder Figma token so
            # figma-console can actually start once a real token is known, and
            # repair a bare markitdown-mcp command that GUI clients may not
            # resolve from PATH.
            if overwrite is False and (figma_token_in(existing) or needs_repair(name, existing)):
                pass  # fall through to replace
            else:
                continue
        current[name] = cfg
        changed.append(name)
    if changed:
        save(path, data)
        print(f"    OK  {label}: added/updated {', '.join(changed)}")
    else:
        print(f"    OK  {label}: already up to date")


def figma_token_in(entry) -> bool:
    """True when an existing figma-console entry still holds the placeholder."""
    try:
        return "YOUR_TOKEN_HERE" in json.dumps(entry)
    except (TypeError, ValueError):
        return False


def desktop_config_paths() -> list[Path]:
    """Every claude_desktop_config.json the installed app(s) actually read."""
    paths: list[Path] = []
    appdata = os.environ.get("APPDATA")
    if appdata:
        classic = Path(appdata) / "Claude" / "claude_desktop_config.json"
        if classic.parent.exists():
            paths.append(classic)
    localappdata = os.environ.get("LOCALAPPDATA")
    if localappdata:
        packages = Path(localappdata) / "Packages"
        if packages.exists():
            for pkg in sorted(packages.glob("Claude_*")):
                cfg_dir = pkg / "LocalCache" / "Roaming" / "Claude"
                if cfg_dir.exists():
                    paths.append(cfg_dir / "claude_desktop_config.json")
    if not paths and appdata:
        # No Desktop found: keep the classic path ready for a future install.
        paths.append(Path(appdata) / "Claude" / "claude_desktop_config.json")
    return paths


def approve_project_mcp_json(claude_json: Path) -> None:
    """Auto-approve the servers in this repo's .mcp.json.

    Claude Code gates project-scoped .mcp.json servers behind a one-time
    approval prompt; until the names land in
    projects["<repo>"].enabledMcpjsonServers the connectors never appear.
    """
    mcp_json = ROOT / ".mcp.json"
    if not mcp_json.exists():
        return
    names = list(load(mcp_json).get("mcpServers", {}).keys())
    if not names:
        return

    data = load(claude_json)
    projects = data.setdefault("projects", {})
    repo_key = str(ROOT).replace("\\", "/")
    # Match the existing key regardless of slash direction or drive-letter case.
    key = next(
        (k for k in projects if k.replace("\\", "/").lower() == repo_key.lower()),
        repo_key,
    )
    proj = projects.setdefault(key, {})
    enabled = proj.setdefault("enabledMcpjsonServers", [])
    disabled = proj.get("disabledMcpjsonServers", [])
    to_add = [n for n in names if n not in enabled and n not in disabled]
    if to_add:
        enabled.extend(to_add)
        save(claude_json, data)
        print(f"    OK  Claude Code: auto-approved .mcp.json servers for {key}: {', '.join(to_add)}")
    else:
        print(f"    OK  Claude Code: .mcp.json servers already approved for {key}")


def main() -> int:
    skip_docling = "--skip-docling" in sys.argv
    skip_desktop = "--skip-desktop" in sys.argv
    token = os.environ.get("FIGMA_ACCESS_TOKEN") or None

    claude_json = Path.home() / ".claude.json"
    register(claude_json, servers(skip_docling, token, False), True, "Claude Code (user scope)")
    approve_project_mcp_json(claude_json)

    if not skip_desktop:
        for cfg in desktop_config_paths():
            register(cfg, servers(skip_docling, token, True), False, f"Claude Desktop ({cfg})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
