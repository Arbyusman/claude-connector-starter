# HyperFrames (heygen-com/hyperframes)

HyperFrames turns HTML/CSS/media into deterministic MP4 video. It ships as a set
of agent skills plus a local CLI. Source: <https://github.com/heygen-com/hyperframes>
— docs: <https://hyperframes.heygen.com>.

Not vendored here: the skill set is large and the CLI is version-coupled, so this
bundle installs it through the upstream CLI instead of freezing a copy.

## Install

Standalone skills (any agent), run inside your project folder:

```bash
npx skills add heygen-com/hyperframes     # choose "Core Skills" in the picker
```

If the HyperFrames plugin is already installed (Claude Code, Copilot, VS Code,
Cursor, Gemini CLI), update instead:

```bash
npx hyperframes skills update
```

Then open or restart your agent in that folder.

## Use

```
/hyperframes make a 10-second product intro for https://example.com
```

Claude Code's plugin router form is `/hyperframes:hyperframes`.

## Preview / render

The agent leaves an editable project folder and opens a local preview. Reopen it
later with:

```bash
npx hyperframes preview
```

Local rendering is free and open-source; optional hosted voice/avatar services
may bill separately.

## Prerequisites

- Node.js (for `npx`).
- A modern browser engine for preview/render (Chromium is fetched by the tooling).
