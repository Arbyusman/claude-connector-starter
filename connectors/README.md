# Connectors bundle

Portable setup for four connectors, targeting **Claude Desktop** (with notes for
Claude Code / Cursor). Everything here is meant to be copyable to another machine
and used as-is.

| # | Connector | Type | What it gives you |
|---|-----------|------|-------------------|
| 1 | **markitdown-mcp** | MCP server (STDIO) | `convert_to_markdown(uri)` — turns PDF, DOCX, PPTX, XLSX, HTML, images, audio, EPUB, YouTube and more into Markdown |
| 2 | **figma-console-mcp** | MCP server (STDIO/`npx`) | Design-system extraction, token sync, design creation, Figma console access |
| 3 | **HyperFrames** (`heygen-com/hyperframes`) | Agent skills + CLI | Author and render MP4 video from HTML/CSS with an agent |
| 4 | **Humanizer** (`blader/humanizer`) | Agent skill | Rewrites AI-sounding prose so it reads like a person wrote it |
| 5 | **Docling MCP** (optional) | MCP server (STDIO) | OCR for scans plus tables and figure captions as Markdown — document images never reach the model as images, which is where the token saving comes from |

> This bundle is designed to be handed off. Copy the whole `connectors/` folder
> somewhere else, run the installer, and it reconfigures that machine.

## Layout

```
connectors/
├── README.md                     ← you are here
├── claude_desktop_config.json    ← ready-to-paste MCP config (both servers)
├── .env.example                  ← Figma token template
├── mcp/
│   ├── markitdown.json           ← local (pip) variant
│   ├── markitdown-docker.json    ← Docker variant (upstream recommended)
│   ├── figma-console.json        ← Figma Console MCP entry
│   ├── cursor.json               ← ready-to-paste Cursor config
│   ├── docling-local.json        ← Docling OCR server (local, offline)
│   ├── docling-remote.json       ← Docling via a Docling Serve instance
│   ├── markitdown-mcp.cmd        ← PATH-independent launcher (Windows)
│   ├── markitdown-mcp.sh         ← PATH-independent launcher (macOS / Linux)
│   └── claude-code.md            ← Claude Code CLI setup
├── skills/
│   ├── humanizer/                ← vendored skill + LICENSE (works offline)
│   └── hyperframes/INSTALL.md    ← how to install HyperFrames skills
├── install.ps1                   ← Windows installer (PowerShell, no bash needed)
├── install.sh                    ← macOS / Linux / Git-Bash installer
├── verify-markitdown.ps1         ← checks markitdown-mcp + convert_to_markdown
├── verify-markitdown.sh          ← same check for macOS / Linux
└── verify-docling.ps1            ← checks the Docling OCR server
```

## Quick start (Windows)

```powershell
cd connectors
pwsh -ExecutionPolicy Bypass -File .\install.ps1            # or: powershell -File .\install.ps1

# add the Docling OCR server too (optional, downloads PyTorch + OCR models)
pwsh -ExecutionPolicy Bypass -File .\install.ps1 -WithDocling
```

The installer:

1. Checks Node.js and Python.
2. Installs the two skills (Humanizer is also copied locally, so it works offline).
3. Installs `markitdown-mcp`.
4. Prompts for your Figma token (or reads `connectors/.env`).
5. Merges the MCP servers into `claude_desktop_config.json` **and** `~/.cursor/mcp.json`
   **without clobbering** your existing servers (a `.bak` backup is written first).

`-WithDocling` / `WITH_DOCLING=1` adds the OCR server; every other step is the same.

## Quick start (macOS / Linux)

```bash
cd connectors
./install.sh

# add the Docling OCR server too
WITH_DOCLING=1 ./install.sh
```

## Manual setup

### 1. markitdown-mcp

```bash
pip install markitdown-mcp
```

**Use Python 3.12 or 3.13.** `markitdown`, `markitdown-mcp` and `magika` all declare
support only up to 3.13, and `onnxruntime` (reached through `magika`) only up to
3.14, so on a newer interpreter pip cannot resolve the stack at all. On a machine
with several versions, pin it:

```bash
py -3.12 -m pip install markitdown-mcp
```

Then add to your MCP config (see the config files in `mcp/`). The server exposes
one tool, `convert_to_markdown(uri)`, where `uri` is any `http:`, `https:`,
`file:`, or `data:` URI.

#### If the client cannot find `markitdown-mcp`

A GUI-spawned client inherits the PATH the app started with, and a per-user pip
install puts the script in a `Scripts` directory that PATH often misses. The
shipped launchers solve that by locating the server themselves — console script
first, then the module through a pinned interpreter (3.13 → 3.12 → 3.11 → `py -3`):

| Platform | Launcher | Client `command` |
|----------|----------|------------------|
| Windows | `mcp/markitdown-mcp.cmd` | `cmd` with `args: ["/c", "C:\\Users\\YOU\\.markitdown-mcp\\markitdown-mcp.cmd"]` |
| macOS / Linux | `mcp/markitdown-mcp.sh` | the script path itself (`chmod +x` it) |

`install.ps1` / `install.sh` copy the right one to `~/.markitdown-mcp/` and point
the client configs at it whenever the bare name is not resolvable — so a Python
upgrade or a PATH change does not break the server again.

Docker alternative (upstream's recommendation) — build once from the repo
(`markitdown-main/packages/markitdown-mcp/Dockerfile`), then use
`mcp/markitdown-docker.json`:

```bash
cd markitdown-main/packages/markitdown-mcp
docker build -t markitdown-mcp:latest .
```

Mount a directory with `-v` if you want the container to read local files. The
server deliberately binds to localhost and has **no authentication** — keep it
local, and treat `convert_to_markdown` as able to read any file your user can read.

### 2. figma-console-mcp

Needs **Node.js 18+** and **Figma Desktop** (the web app is not enough).

1. Create a Figma personal access token (starts with `figd_`) with scopes:
   File content (Read), File versions (Read), Variables (Read), Comments (Read and write).
2. Put it in the config env block (see `mcp/figma-console.json`) or `connectors/.env`.
3. In Figma Desktop, import the Desktop Bridge plugin:
   `Plugins → Development → Import plugin from manifest…` and select
   `~/.figma-console-mcp/plugin/manifest.json` (auto-created on first server run).

Config:

```json
{
  "figma-console": {
    "command": "npx",
    "args": ["-y", "figma-console-mcp@latest"],
    "env": {
      "FIGMA_ACCESS_TOKEN": "figd_YOUR_TOKEN_HERE",
      "ENABLE_MCP_APPS": "true"
    }
  }
}
```

Optional read-only browser mode (no Node, no token): point the client at the
remote SSE endpoint via `npx -y mcp-remote https://figma-console-mcp.southleft.com/sse`.

### 3. Where each client reads its MCP config

| Client | Windows | macOS | Linux |
|--------|---------|-------|-------|
| Claude Desktop (classic installer) | `%APPDATA%\Claude\claude_desktop_config.json` | `~/Library/Application Support/Claude/claude_desktop_config.json` | `~/.config/Claude/claude_desktop_config.json` |
| Claude Desktop (MSIX / Microsoft Store) | `%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\claude_desktop_config.json` | — | — |
| Cursor | `%USERPROFILE%\.cursor\mcp.json` | `~/.cursor/mcp.json` | `~/.cursor/mcp.json` |
| Claude Code | `claude mcp add` (see `mcp/claude-code.md`) | — | — |

Both the Desktop and Cursor files take the same `mcpServers` shape, so the same
block works in each. The installers write every location that already exists
(Claude Code uses the CLI, printed as a note).

**The Store build is easy to miss.** A packaged app's `%APPDATA%` is redirected
into its package container, so writing only `%APPDATA%\Claude` produces a config
that looks perfect on disk and never reaches the app that is actually installed.
The packaged file may also already hold the app's own preferences
(`coworkUserFilesPath`, `preferences`, `epitaxyPrefs`); merge `mcpServers` into it
rather than replacing it — the installer does.

Server logs for either build are at `%LOCALAPPDATA%\Claude\logs\`: `mcp.log`
lists every server the client started, and one `mcp-server-<name>.log` per server.
A server that never appears there was never launched.

> Note: this Claude Desktop also runs some connectors as **Claude Extensions**
> (DXT bundles, seen in `Claude Extensions/` and `extensions-installations.json`,
> each with its own `mcp_config`). The bundled Filesystem server is one of those.
> Servers added through `mcpServers` and servers installed as extensions appear in
> the same tool list; use the extension route from Settings when a connector ships
> as a DXT bundle, and `mcpServers` for a plain stdio command like these.

### 4. Cursor

Cursor uses the same format as Claude Desktop. Either let the installer write it,
or copy `mcp/cursor.json` to `%USERPROFILE%\.cursor\mcp.json` (Windows) /
`~/.cursor/mcp.json` (macOS, Linux), keeping any `mcpServers` you already have.
Restart Cursor, then check Settings → MCP.

### 5. Claude Code

Claude Code is configured through its CLI, not a JSON file. From any terminal:

```bash
claude mcp add markitdown -s user -- markitdown-mcp
claude mcp add figma-console -s user \
  -e FIGMA_ACCESS_TOKEN=figd_YOUR_TOKEN_HERE \
  -e ENABLE_MCP_APPS=true \
  -- npx -y figma-console-mcp@latest
claude mcp list
```

Full details, including the project-scoped `.mcp.json` alternative, are in
`mcp/claude-code.md`.

### 6. Humanizer skill

Canonical install (any agent):

```bash
npx skills add blader/humanizer --global --agent claude-code
```

Or upload as a skill: Claude.ai / Claude Desktop → Settings → Skills → upload the
`skills/humanizer/` folder zipped. A vendored copy lives in this bundle, so it
works with no network. Call it with `/humanizer`.

### 7. HyperFrames skills

```bash
npx skills add heygen-com/hyperframes     # choose "Core Skills"
# or, if the plugin is already installed:
npx hyperframes skills update
```

See `skills/hyperframes/INSTALL.md` for the plugin path (Claude Code, Cursor,
Copilot, VS Code, Gemini CLI) and the `/hyperframes` command.

### 8. Verify markitdown-mcp works

`markitdown-mcp` exposes one tool, `convert_to_markdown(uri)`. Confirm the server
starts and the tool actually converts something before wiring it into a client:

```powershell
powershell -ExecutionPolicy Bypass -File .\verify-markitdown.ps1
```

```bash
./verify-markitdown.sh
```

Both scripts run three checks through the MCP Inspector CLI and exit non-zero if
any of them fail: the server resolves, `tools/list` exposes `convert_to_markdown`,
and `tools/call` converts a generated HTML sample.

The equivalent commands by hand:

```bash
# list the tools (expect convert_to_markdown)
npx -y @modelcontextprotocol/inspector --cli markitdown-mcp --method tools/list

# call it on any http:, https:, file: or data: URI
npx -y @modelcontextprotocol/inspector --cli markitdown-mcp \
  --method tools/call --tool-name convert_to_markdown \
  --tool-arg uri=file:///C:/path/to/input.html
```

Prefer a browser? `npx -y @modelcontextprotocol/inspector`, then select transport
**STDIO**, command `markitdown-mcp`, click Connect → **Tools** → **List Tools** →
`convert_to_markdown` → run it with any valid URI.

Inspector exit codes worth knowing: `0` success, `4` server unreachable, `5` tool
error or tool not found.

### 9. Docling — reading images inside documents (token saving)

`markitdown` turns a document into Markdown but does not OCR. Docling does: it
reads scanned PDFs and images, keeps tables as tables, and emits figure captions,
while **leaving images out of the transcript** — that is what saves tokens. A page
image costs hundreds to thousands of tokens; the same page as OCR'd text usually
costs a fraction of that, and the model can quote it.

Two ways to run it:

| Mode | Config | Pros | Cons |
|------|--------|------|------|
| **Local** | `mcp/docling-local.json` | Free, offline, nothing leaves the machine | First run downloads PyTorch + OCR models (~2-3 GB); slow on CPU |
| **Remote** | `mcp/docling-remote.json` | Light client, fast | Needs a [Docling Serve](https://github.com/docling-project/docling-serve) instance + API key |

Local entry (what `-WithDocling` writes):

```json
{
  "docling": {
    "command": "uvx",
    "args": ["--from", "docling-mcp[local]", "docling-mcp-server", "--transport", "stdio"],
    "env": {
      "DOCLING_MCP_CONVERSION_MODE": "local",
      "DOCLING_MCP_KEEP_IMAGES": "false",
      "DOCLING_MCP_IMAGE_EXPORT_MODE": "placeholder",
      "DOCLING_MCP_DO_OCR": "true",
      "DOCLING_MCP_DO_TABLE_STRUCTURE": "true",
      "DOCLING_MCP_DO_PICTURE_DESCRIPTION": "false"
    }
  }
}
```

`uvx` ships with [uv](https://docs.astral.sh/uv/) (`winget install --id astral-sh.uv -e`
on Windows). Without uvx, install with pip and drop the `--from ...` args:

```bash
pip install "docling-mcp[local]"     # then command: docling-mcp-server
```

Without uv/pip you can skip the install entirely: `npx -y mcp-remote <docling-serve-url>`
against a hosted Docling Serve endpoint.

The settings that do the token saving:

- `DOCLING_MCP_KEEP_IMAGES=false` — do not carry page images in the output.
- `DOCLING_MCP_IMAGE_EXPORT_MODE=placeholder` — images become `<!-- image -->` in
the Markdown instead of base64 data URIs (base64 is by far the biggest token sink).
- `DOCLING_MCP_DO_OCR=true` — OCR the pages that have no text layer.
- `DOCLING_MCP_DO_PICTURE_DESCRIPTION=true` (optional) — ask a small vision model
(`DOCLING_MCP_PICTURE_DESCRIPTION_PRESET=smolvlm`) to describe each figure in *text*.
This is the only setting that lets the agent "see" pictures while still paying text
prices, but it is slow on CPU. Converted once, the description is cached in the
DoclingDocument, so later questions about the same file cost nothing extra.

> **Why not the OCR plugin in this repo?** `packages/markitdown-ocr` exists and does
exactly this, but it needs `llm_client` **and** `llm_model` kwargs to build its OCR
service, and `markitdown-mcp` calls `MarkItDown(enable_plugins=...)` without them
(`packages/markitdown-mcp/src/markitdown_mcp/__main__.py`). The plugin therefore
loads and *silently skips OCR*. Setting `MARKITDOWN_ENABLE_PLUGINS=true` alone does
not enable image OCR through the MCP server — that needs a patch to pass the client
through (or the `markitdown` CLI: `markitdown in.pdf --use-plugins --llm-client openai --llm-model gpt-4o`).

Requirements: **Python 3.10+** locally (or uv, which manages its own), and a client
on MCP Python SDK v2. `docling-mcp>=3.0.0` targets that SDK; on an older client pin
`pip install "docling-mcp<3.0.0"`.

The tools it exposes (conversion group, the default):

| Tool | Purpose |
|------|---------|
| `convert_document_into_docling_document` | Convert a PDF/DOCX/HTML/**image** from a path or URL |
| `convert_directory_files_into_docling_document` | Convert every file in a folder |
| `check_document_in_local_cache` / `list_cached_documents` | See what is already parsed (free to ask twice) |
| `remove_document_from_local_cache` | Drop a document and free its memory |
| `export_docling_document_to_markdown` | Emit the Markdown the model reads |

Converting and reading are two steps, so the agent caches once and exports as
many times as it likes:

```text
convert_document_into_docling_document  -> { document_key: "..." }
export_docling_document_to_markdown     -> the Markdown, images as <!-- image -->
```

Verify the server (tools/list only, fast):

```powershell
powershell -ExecutionPolicy Bypass -File .\verify-docling.ps1

# also run a real conversion - first run downloads the models
powershell -ExecutionPolicy Bypass -File .\verify-docling.ps1 -Convert
```

By hand, note the `--`: the Inspector has its own `--transport` flag and would
otherwise swallow the one the server needs.

```bash
npx -y @modelcontextprotocol/inspector --cli --method tools/list \
  -- uvx --from "docling-mcp[local]" docling-mcp-server --transport stdio
```

## Troubleshooting

- **`skills add` fails on Windows.** It needs a non-interactive run and symlinks
  disabled: `npx -y skills add <owner/repo> -g -a claude-code -y --copy`. It also
  shells out to `git`, so install Git for Windows first.
- **`ERROR: Cannot install markitdown because these package versions have
  conflicting dependencies.`** Your interpreter is too new. `markitdown`,
  `markitdown-mcp` and `magika` support up to Python 3.13 and `onnxruntime` up to
  3.14, so on 3.15 pip backtracks through every version and then gives up. Install
  3.12 and pin it: `py -3.12 -m pip install markitdown-mcp`. The installer detects
  this and skips the doomed attempt instead of burning minutes on it.
- **`pip`/`py` not found.** Python is not installed (or not on `PATH`). Either
  `winget install --id Python.Python.3.12 -e --source winget`, or — if the machine
  uses the **Python install manager** (runtimes under `%LOCALAPPDATA%\Python`, shims
  in `%LOCALAPPDATA%\Python\bin`) — `py install 3.12`, then reopen the terminal.
  The two are different installations, and only one of them is what `py` resolves to.
- **A version selector resolves elsewhere.** `py -3.13` can hand back a different
  interpreter than the selector names (seen: 3.15 from a `py -3.13` probe). Every
  client config must therefore point at a path, or at the launcher in `mcp/`, rather
  than at a selector. The installer asks each candidate for `sys.version_info` and
  ranks the answers instead of trusting the selector.
- **A working `py` probe "fails" with exit code -1610612730.** That status is
  STATUS 0xC0000135: PowerShell runs the `py` shim as an App Execution Alias stub
  and reports a crash even when the launcher succeeds and prints a version, so
  `$LASTEXITCODE` after it cannot be trusted. (A bare `pip` can also hide an
  unsupported runtime behind that shim — seen: runs on 3.15 while 3.12 is the one
  with packages.) The installer works around the shim by re-testing a suspicious
  candidate inside `cmd.exe` and by trusting the printed version text; the same
  fix is why plain `pip ...` in a shell can quietly install into the wrong
  interpreter while `py -3.12 -m pip ...` stays correct.
- **`docling` fails with `spawn docling-mcp-server ENOENT`.** The server was
  pip-installed per-user, so the script landed in
  `%LOCALAPPDATA%\Python\pythoncore-3.12-64\Scripts` — a directory GUI clients
  do not have on their PATH, so the bare name cannot spawn. The installer now
  resolves the real `docling-mcp-server.exe` after install and writes its
  absolute path into the client configs (same treatment as markitdown). Test the
  script on its own:
  `%LOCALAPPDATA%\Python\pythoncore-3.12-64\Scripts\docling-mcp-server.exe --transport stdio`
  should sit waiting for JSON-RPC on stdin.
- **`pip install "docling-mcp[local]"` ends in "conflicting dependencies".** The
  `[local]` extra pins `docling-core[chunking]`, whose `tree-sitter` range does
  not resolve under this pip, so the resolver gives up. Plain `docling-mcp` (no
  extra) installs fine, and `docling[standard]` adds the OCR runtime separately:

        py -3.12 -m pip install docling-mcp
        py -3.12 -m pip install "docling[standard]"

  The installer retries in that order automatically. Conversion works without
  the extra; OCR needs the second install.
- **`markitdown` shows no tools in the client.** Check the `command` path: after a
  per-user install the script lives in `%APPDATA%\Python\Python3xx\Scripts` and may
  not be on the PATH a GUI client sees. On a machine using the Python install
  manager, pip-created scripts are instead shimmed into `%LOCALAPPDATA%\Python\bin`
  (same place as `py.exe`), which *is* on PATH — so there the bare name usually
  resolves on its own. `install.ps1` points the config at
  `~/.markitdown-mcp/markitdown-mcp.cmd` (via `cmd /c`) when it cannot resolve the
  bare name, and falls back to the script's absolute path only if that copy fails.
  Test the launcher on its own before suspecting the client:
  `%USERPROFILE%\.markitdown-mcp\markitdown-mcp.cmd` should sit there waiting for
  JSON-RPC on stdin, and print `markitdown-mcp is not installed` on stderr if the
  package is missing.
- **I expected OCR but got image placeholders.** Check which server did the work:
  `markitdown` never OCRs (see the note in §9); `docling` needs
  `DOCLING_MCP_DO_OCR=true`, and pictures only become text when
  `DOCLING_MCP_DO_PICTURE_DESCRIPTION=true`.
- **I edited `claude_desktop_config.json` and nothing shows up.** You edited the
  file for the other build. Check for
  `%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\claude_desktop_config.json`
  (Store/MSIX) alongside `%APPDATA%\Claude\claude_desktop_config.json` (classic) and
  put `mcpServers` in the one whose folder is actually in use — the packaged
  folder is the one carrying `Claude Extensions/`, `IndexedDB/` and session data.
  Then confirm in `%LOCALAPPDATA%\Claude\logs\mcp.log` that the client started the
  server.
- **`npx` not found in Claude Desktop on Windows.** Some builds need the shell
  wrapper. Use `"command": "cmd", "args": ["/c", "npx", "-y", "figma-console-mcp@latest"]`.
- **`markitdown-mcp` not found.** Ensure pip's Scripts dir is on `PATH`, or use the
  absolute path to `markitdown-mcp.exe` as the `command`.
- **Figma tools return nothing.** Start the server once, then re-import
  `~/.figma-console-mcp/plugin/manifest.json` in Figma Desktop and run the plugin.
- **JSON won't load.** `claude_desktop_config.json` must be valid JSON: no comments,
  no trailing commas.
- **Want to confirm markitdown before blaming the client?** Run
  `verify-markitdown.ps1` / `verify-markitdown.sh`. If the Inspector passes but the
  client shows nothing, the problem is the client config (path or `PATH`), not the server.

## Licenses

- markitdown-mcp — MIT (Microsoft).
- Docling / docling-mcp — MIT (IBM Research Zurich, LF AI & Data).
- figma-console-mcp — see [southleft/figma-console-mcp](https://github.com/southleft/figma-console-mcp).
- HyperFrames — see [heygen-com/hyperframes](https://github.com/heygen-com/hyperframes).
- Humanizer — MIT, vendored in `skills/humanizer/` with its LICENSE.
