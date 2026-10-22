# D:\arby\ai — AI tooling workspace

## Layout
- `connectors/` — portable installer bundle for MCP servers + skills (Claude Desktop / Cursor / Claude Code). See `connectors/README.md`.
- `markitdown-main/` — vendored upstream copy of microsoft/markitdown. Treat as read-only; don't read or search it unless the task is about it.

## MCP servers (project `.mcp.json`)
- `markitdown` — `convert_to_markdown(uri)` for PDF/DOCX/PPTX/XLSX/HTML/EPUB/YouTube.
- `docling` — OCR for scanned PDFs/images, tables as Markdown (images replaced by placeholders).
- `figma-console` — Figma design-system access. Needs `FIGMA_ACCESS_TOKEN` env var.

## Token-saving rules
- Never Read a PDF, Office file or image directly. Convert first: `markitdown` for digital docs, `docling` for scans. Save long output to a `.md` file and read only the parts needed.
- Use Grep/Glob to locate code; Read with `offset`/`limit` instead of whole large files.
- Don't re-read files just edited. Keep answers short; no recaps of unchanged code.
- Skip `markitdown-main/`, `.git/`, `node_modules/` in searches.
- Use `/compact` when a task phase ends; `/clear` between unrelated tasks.

## Environment
- Windows 11, Git Bash. Python: use `py -3.12` (3.15 is default but markitdown doesn't support it). Node via `npx`.
