# Panduan Setup Connector Claude (Claude Code + Claude Desktop)

Panduan ini menjelaskan **di mana Claude membaca config connector (MCP)**,
**cara menulisnya di JSON**, dan **cara kerja auto-setup** di repo ini supaya
connector (markitdown, docling, docimage, figma-console, canva) **muncul
otomatis** tanpa prompt approve manual.

---

## Kenapa dulu tidak muncul otomatis?

Ada 3 penyebab yang ditemukan di mesin ini (Windows 11):

| # | Penyebab | Akibat |
|---|----------|--------|
| 1 | Claude Code punya *approval prompt* untuk `.mcp.json` project. Nama server harus masuk `enabledMcpjsonServers` di `~/.claude.json`. | Server ada di `.mcp.json` tapi tidak pernah muncul karena belum di-approve. |
| 2 | Claude Desktop versi **Microsoft Store (MSIX)** membaca config di `%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\claude_desktop_config.json`, **bukan** `%APPDATA%\Claude\`. Register script lama hanya menulis `%APPDATA%`. | Config terlihat benar di disk tapi app yang terpasang tidak pernah membacanya. |
| 3 | Config Desktop masih memakai command telanjang `markitdown-mcp` dan token Figma placeholder `figd_YOUR_TOKEN_HERE`. | Server gagal start, connector tidak muncul / error. |

Ketiganya sudah diperbaiki di `tools/register_mcp.py` (dijalankan otomatis oleh
`setup.cmd` / `setup.ps1` langkah 6/7).

---

## 1. Di mana Claude Code membaca config

Claude Code punya 2 scope:

| Scope | File | Kapan dipakai |
|-------|------|---------------|
| **User** | `~/.claude.json` (`C:\Users\YOU\.claude.json`) → key `mcpServers` | Di **semua** project. Ini yang ditulis `register_mcp.py`. |
| **Project** | `.mcp.json` di root repo | Hanya repo ini, dan **harus di-approve sekali** lewat `enabledMcpjsonServers`. |

### Bentuk JSON (user scope) — `~/.claude.json`

```json
{
  "mcpServers": {
    "markitdown": {
      "command": "C:\\Users\\YOU\\AppData\\Local\\Python\\pythoncore-3.12-64\\python.exe",
      "args": ["-m", "markitdown_mcp"]
    },
    "docling": {
      "command": "C:\\Users\\YOU\\AppData\\Local\\Python\\pythoncore-3.12-64\\python.exe",
      "args": ["-c", "from docling_mcp.servers.mcp_server import app; app()", "--transport", "stdio"],
      "env": {
        "DOCLING_MCP_CONVERSION_MODE": "local",
        "DOCLING_MCP_KEEP_IMAGES": "false",
        "DOCLING_MCP_IMAGE_EXPORT_MODE": "placeholder",
        "DOCLING_MCP_DO_OCR": "true",
        "DOCLING_MCP_DO_TABLE_STRUCTURE": "true",
        "DOCLING_MCP_DO_PICTURE_DESCRIPTION": "false"
      }
    },
    "docimage": {
      "command": "C:\\Users\\YOU\\AppData\\Local\\Python\\pythoncore-3.12-64\\python.exe",
      "args": ["D:\\arby\\ai\\tools\\docimage_mcp.py"]
    },
    "figma-console": {
      "command": "npx",
      "args": ["-y", "figma-console-mcp@latest"],
      "env": {
        "FIGMA_ACCESS_TOKEN": "${FIGMA_ACCESS_TOKEN}",
        "ENABLE_MCP_APPS": "true"
      }
    },
    "canva": { "type": "http", "url": "https://mcp.canva.com/mcp" }
  }
}
```

Catatan:

- **Pakai path python absolut** (seperti di atas), jangan `py -3.12`. Client GUI
  tidak selalu punya `py` di PATH-nya, dan selector `py` bisa salah resolve.
- Claude Code **mer-expand** `${FIGMA_ACCESS_TOKEN}` dari environment; karena itu
  user scope boleh memakai `${...}`, sedangkan Claude Desktop harus nilai literal.
- `canva` adalah remote HTTP server (OAuth) — Claude Desktop mendapatkannya dari
  Settings → Connectors, jadi tidak ditulis ke config Desktop.

### Auto-approve `.mcp.json` project

Claude Code menanyakan "approve server di .mcp.json?" sekali per project.
Supaya tidak perlu approve manual, `register_mcp.py` menulis nama-nama server
dari `.mcp.json` repo ini ke `~/.claude.json`:

```json
{
  "projects": {
    "D:/arby/ai": {
      "enabledMcpjsonServers": ["markitdown", "docling", "docimage", "canva", "figma-console"]
    }
  }
}
```

Setelah itu, buka Claude Code di `D:\arby/ai` — semua connector langsung aktif.

### Verifikasi

```bash
claude mcp list          # harus menampilkan semua server + status ✓
```

Atau di dalam sesi Claude Code: `/mcp` untuk melihat daftar & status tiap server.

> **Penting:** jalankan `register_mcp.py` **selagi Claude Code tertutup**.
> Claude Code menulis ulang `~/.claude.json` saat keluar, sehingga perubahan
> dari luar bisa tertimpa.

---

## 2. Di mana Claude Desktop membaca config

| Build | Lokasi config (Windows) |
|-------|-------------------------|
| Installer klasik | `%APPDATA%\Claude\claude_desktop_config.json` |
| **Microsoft Store (MSIX)** | `%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\claude_desktop_config.json` |

Mesin ini memakai **build Store**
(`Claude_pzs8sxrjxfjjc`). Itu sebabnya config yang benar harus ditulis ke
LocalCache — `%APPDATA%\Claude\` yang berisi config lama **tidak dibaca app**.

`register_mcp.py` sekarang menulis ke **semua lokasi yang ada** (kedua-duanya,
kalau keduanya ada), tanpa menghapus key lain (preferences, dst), plus backup
`.bak` ber-timestamp.

Bentuk JSON-nya sama dengan user scope Claude Code di atas, dengan 2 beda:

1. `figma-console` memakai **token literal**, bukan `${...}`.
2. Tidak ada entry `canva`.

Setelah config ditulis: **restart Claude Desktop** (Quit dari system tray, lalu
buka lagi). Cek di Settings → Connectors / Developer → MCP Servers.

Log server: `%LOCALAPPDATA%\Claude\logs\mcp.log` (server yang tidak pernah
muncul di log = tidak pernah di-spawn).

---

## 3. Cara pakai auto-setup (starter tanpa bug)

```powershell
# sekali jalan, idempotent (aman diulang):
powershell -ExecutionPolicy Bypass -File .\setup.ps1

# opsi:
.\setup.ps1 -SkipDocling        # skip install OCR ~2-3 GB
.\setup.ps1 -FigmaToken figd_xxx # sekalian simpan token Figma
.\setup.ps1 -WithDesktop         # + configure Claude Desktop & Cursor
```

Alur `setup.ps1`:

1. Install tool sistem (Git, Node, Python 3.12, uv, FFmpeg) via winget — skip kalau sudah ada.
2. Install `markitdown-mcp` + dependensi docimage via `py -3.12 -m pip`.
3. Install `docling-mcp` (OCR, opsional).
4. Install skills (Humanizer offline, HyperFrames).
5. Simpan token Figma ke environment user.
6. **Register semua server** ke Claude Code (`~/.claude.json`, user scope +
   auto-approve `.mcp.json`) dan Claude Desktop (**semua** lokasi config).
7. Smoke-test tiap server (handshake `initialize` JSON-RPC).

Kalau ada warning di akhir, biasanya cukup: buka terminal baru (PATH refresh),
lalu jalankan ulang `setup.cmd`.

Daftar ulang tanpa install ulang:

```powershell
py -3.12 tools\register_mcp.py            # Claude Code + Claude Desktop
py -3.12 tools\register_mcp.py --skip-docling
```

---

## 4. Troubleshooting cepat

| Gejala | Penyebab / solusi |
|--------|-------------------|
| `/mcp` di Claude Code kosong | Config tertimpa session yang masih buka. Tutup Claude Code, jalankan ulang `py -3.12 tools\register_mcp.py`, buka lagi. |
| Server project `.mcp.json` diminta approve | `enabledMcpjsonServers` belum terisi — jalankan ulang register script (otomatis approve). |
| Connector tidak muncul di Desktop padahal config benar | Anda edit file build lain. Cek LocalCache (Store) vs `%APPDATA%` (klasik) — lihat tabel §2. |
| figma-console error auth | Token masih placeholder `figd_YOUR_TOKEN_HERE`. Isi token: `setup.ps1 -FigmaToken figd_xxx`, lalu register ulang + restart client. |
| `spawn markitdown-mcp ENOENT` | Command telanjang tidak ketemu di PATH client. Register script memakai path python absolut — jalankan ulang register. |
| Server muncul tapi tool error saat dipakai | Test handshake manual: `echo '{"jsonrpc":"2.0","id":1,"method":"initialize",...}' | py -3.12 -m markitdown_mcp` harus balas `serverInfo`. |

---

## File terkait

- `tools/register_mcp.py` — register otomatis ke Claude Code + Claude Desktop (semua build).
- `setup.ps1` / `setup.cmd` — starter satu-klik (langkah 6 memanggil register script).
- `.mcp.json` — config project scope untuk Claude Code.
- `connectors/claude_desktop_config.json` — template siap-paste untuk Desktop.
- `connectors/mcp/claude-code.md` — setup via CLI `claude mcp add` (versi Inggris).
