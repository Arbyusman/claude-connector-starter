# Claude Code setup

Claude Code configures MCP servers through the `claude mcp add` CLI rather than a
JSON file you edit by hand. Run these from any terminal.

## MCP servers

```bash
# markitdown
claude mcp add markitdown -s user -- markitdown-mcp

# figma-console (replace the token)
claude mcp add figma-console -s user \
  -e FIGMA_ACCESS_TOKEN=figd_YOUR_TOKEN_HERE \
  -e ENABLE_MCP_APPS=true \
  -- npx -y figma-console-mcp@latest
```

`-s user` = available in every project. Use `-s project` to write a shared
`.mcp.json` into the current repo instead.

Verify:

```bash
claude mcp list
```

## Skills

```bash
# Humanizer
npx skills add blader/humanizer --global --agent claude-code

# HyperFrames (choose "Core Skills" when prompted)
npx skills add heygen-com/hyperframes --global --agent claude-code
```

Once installed, call them with `/humanizer` and `/hyperframes`.

## Alternative: project-scoped config

Claude Code also reads a `.mcp.json` in the project root with the same
`mcpServers` shape as `mcp/cursor.json` / `claude_desktop_config.json`. Copy one
of those into your repo as `.mcp.json` if you prefer file-based config.

## Where Claude Code stores user config

- Windows: `%USERPROFILE%\.claude.json`
- macOS / Linux: `~/.claude.json`
