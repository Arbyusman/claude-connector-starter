# D:\arby\ai — AI tooling workspace

## Layout
- `connectors/` — portable installer bundle for MCP servers + skills (Claude Desktop / Cursor / Claude Code). See `connectors/README.md`.
- `docs/claude-mcp-setup.md` — panduan (ID): di mana Claude membaca config JSON, auto-register & troubleshooting connector tidak muncul.
- `markitdown-main/` — vendored upstream copy of microsoft/markitdown. Treat as read-only; don't read or search it unless the task is about it.

## MCP servers (project `.mcp.json`)
- `markitdown` — `convert_to_markdown(uri)` for PDF/DOCX/PPTX/XLSX/HTML/EPUB/YouTube.
- `docling` — OCR for scanned PDFs/images, tables as Markdown (images replaced by placeholders).
- `docimage` (`tools/docimage_mcp.py`) — images inside .docx/.pdf: `list_images` → `read_image` (downscaled), `extract_images`, `render_pdf_page`, `insert_image_docx`, `insert_image_pdf`. Edits write `<name>.edited.<ext>`, never the original.
- `canva` — official Canva remote MCP (OAuth; authenticate once via `/mcp`).
- `figma-console` — Figma design-system access. Needs `FIGMA_ACCESS_TOKEN` env var.

Setup on a new machine: run `setup.cmd` (installs everything and registers the servers with Claude Code + Claude Desktop).

## Token-saving rules
- For images in documents: `list_images` first, then `read_image` only the ones needed, with a small `max_dim` (512-1024).
- Never Read a PDF, Office file or image directly. Convert first: `markitdown` for digital docs, `docling` for scans. Save long output to a `.md` file and read only the parts needed.
- Use Grep/Glob to locate code; Read with `offset`/`limit` instead of whole large files.
- Don't re-read files just edited. Keep answers short; no recaps of unchanged code.
- Skip `markitdown-main/`, `.git/`, `node_modules/` in searches.
- Use `/compact` when a task phase ends; `/clear` between unrelated tasks.

## Environment
- Windows 11, Git Bash. Python: use `py -3.12` (3.15 is default but markitdown doesn't support it). Node via `npx`.
