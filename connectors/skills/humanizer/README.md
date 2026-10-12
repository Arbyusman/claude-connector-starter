# Humanizer (vendored)

Source: [blader/humanizer](https://github.com/blader/humanizer) — v3.1.0, MIT.
Vendored so it works with no network. `SKILL.md` is the canonical skill file;
`LICENSE` is upstream's license.

## Install

Canonical (keeps it updated):

```bash
npx skills add blader/humanizer --global --agent claude-code
```

Offline / Claude Desktop:

- Copy this folder (or a ZIP of it) into your agent's skills directory, e.g.
  `~/.claude/skills/humanizer/SKILL.md`.
- Claude.ai / Claude Desktop: Settings → Skills → upload.

## Use

```
/humanizer
[paste text]
```

Or in plain language: `Please humanize this text: ...`
