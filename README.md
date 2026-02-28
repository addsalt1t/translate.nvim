# translate.nvim

Minimal translation plugin for Neovim with DeepL and Google Cloud Translation engines.

![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-green?logo=neovim)
![License](https://img.shields.io/badge/License-MIT-blue)
![Lua](https://img.shields.io/badge/Lua-blue?logo=lua)

## Features

- Translate visual selections with a single keymap
- DeepL and Google Cloud Translation API v2 support
- Floating window output with centered engine title in border
- Target language picker (`vim.ui.select`) per engine
- Engine switcher with automatic target language normalization
- Persist last-used engine and target language across sessions
- Preserve original line structure: blank lines and leading indentation are kept intact
- Parallel chunking for large selections (50 lines per request)
- Race guard: rapid re-translations cancel stale in-flight requests
- Security: API keys are passed via curl stdin (`--config -`), never as CLI arguments

## Requirements

- Neovim 0.10+ (`vim.system()` required)
- `curl` in `$PATH`
- At least one API key:
  - **DeepL**: `DEEPL_AUTH_KEY` environment variable or `setup({ api_key = "..." })`
  - **Google**: `GOOGLE_TRANSLATE_API_KEY` or `GOOGLE_API_KEY` environment variable, or `setup({ google_api_key = "..." })`

## Installation

### lazy.nvim

```lua
{
  "addsalt1t/translate.nvim",
  opts = {
    api_key = vim.env.DEEPL_AUTH_KEY,
  },
}
```

### packer.nvim

```lua
use({
  "addsalt1t/translate.nvim",
  config = function()
    require("translate").setup({
      api_key = vim.env.DEEPL_AUTH_KEY,
    })
  end,
})
```

### Local Development

```lua
{
  dir = "/path/to/translate.nvim",
  name = "translate.nvim",
  config = function()
    require("translate").setup()
  end,
}
```

## Configuration

The plugin auto-calls `setup()` on load with sensible defaults. Override any option as needed.

### Default configuration

```lua
require("translate").setup({
  api_key = vim.env.DEEPL_AUTH_KEY,
  google_api_key = vim.env.GOOGLE_TRANSLATE_API_KEY or vim.env.GOOGLE_API_KEY,
  engine = "deepl",
  engine_labels = {
    deepl = "DeepL",
    google = "Google",
  },
  free_api = true,
  default_target = "KO",
  persist_target = true,
  state_path = vim.fs.normalize(vim.fn.stdpath("state") .. "/translate.nvim/state.json"),
  keymaps = {
    translate_visual = "<Space>tr",
    select_target = "<Space>tl",
    select_engine = "<Space>te",
  },
  float = {
    border = "rounded",
    winhighlight = "NormalFloat:Normal,FloatBorder:Normal",
    size_base = "window",
    width_ratio = 1.0,
    height_ratio = 1.0,
    width_offset = 0,
    height_offset = 0,
    min_width = 40,
    min_height = 8,
    inherit_view = true,
    center_vertical = false,
    -- width = 100,    -- absolute override (skips ratio calculation)
    -- height = 14,    -- absolute override (skips ratio calculation)
  },
})
```

### Option reference

| Option | Type | Default | Description |
|---|---|---|---|
| `api_key` | `string?` | `$DEEPL_AUTH_KEY` | DeepL API authentication key |
| `google_api_key` | `string?` | `$GOOGLE_TRANSLATE_API_KEY` | Google Cloud Translation API key |
| `engine` | `string` | `"deepl"` | Active translation engine (`"deepl"` or `"google"`) |
| `engine_labels` | `table` | `{ deepl="DeepL", google="Google" }` | Display labels for engine names |
| `free_api` | `boolean` | `true` | Use DeepL free API endpoint (`api-free.deepl.com`) |
| `default_target` | `string` | `"KO"` | Fallback target language when current is invalid for engine |
| `persist_target` | `boolean` | `true` | Save engine and target language to disk between sessions |
| `state_path` | `string` | `stdpath("state").."/translate.nvim/state.json"` | Absolute path for persisted state file |
| `keymaps.translate_visual` | `string` | `"<Space>tr"` | Keymap to translate visual selection |
| `keymaps.select_target` | `string` | `"<Space>tl"` | Keymap to open target language picker |
| `keymaps.select_engine` | `string` | `"<Space>te"` | Keymap to open engine picker |

### Float window options

| Option | Type | Default | Description |
|---|---|---|---|
| `float.border` | `string` | `"rounded"` | Border style (see `:h nvim_open_win`) |
| `float.winhighlight` | `string` | `"NormalFloat:Normal,FloatBorder:Normal"` | Window highlight groups |
| `float.size_base` | `string` | `"window"` | Base dimensions from `"window"` or `"editor"` |
| `float.width_ratio` | `number` | `1.0` | Width as fraction of base (0.0-1.0) |
| `float.height_ratio` | `number` | `1.0` | Height as fraction of base (0.0-1.0) |
| `float.width_offset` | `number` | `0` | Additive columns after ratio calculation |
| `float.height_offset` | `number` | `0` | Additive rows after ratio calculation |
| `float.min_width` | `integer` | `40` | Minimum window width in columns |
| `float.min_height` | `integer` | `8` | Minimum window height in rows |
| `float.width` | `integer?` | `nil` | Absolute width override (skips ratio) |
| `float.height` | `integer?` | `nil` | Absolute height override (skips ratio) |
| `float.inherit_view` | `boolean` | `true` | Copy `tabstop`, `shiftwidth`, etc. from source window |
| `float.center_vertical` | `boolean` | `false` | Vertically center short text in the float |

> **Deprecated:** `max_width_ratio` and `max_height_ratio` are silently migrated to `width_ratio`/`height_ratio`.

### Engine selection priority

The active engine is resolved in this order:

1. Explicit `engine` option passed to `setup()`
2. Saved engine from state file (if `persist_target = true`)
3. First-run auto-prefer: `"google"` when both API keys are present and no saved state
4. Base default: `"deepl"`

## Translation Engines

### Provider comparison

| | DeepL | Google Cloud Translation |
|---|---|---|
| API | DeepL API v2 | Cloud Translation API v2 |
| Target languages | 35 | 109 |
| API key env var | `DEEPL_AUTH_KEY` | `GOOGLE_TRANSLATE_API_KEY` / `GOOGLE_API_KEY` |
| Auth method | `Authorization` header | `X-Goog-Api-Key` header |
| Free tier | `free_api = true` (default) | N/A (pay-per-use) |
| Max texts/request | 50 | 50 |
| Language codes | Region-specific (e.g. `EN-US`, `PT-BR`) | Simple (e.g. `EN`, `PT`) |

### Engine switching

When switching engines via `:TranslateSelectEngine` or `set_engine()`:

- The current target language is normalized and validated for the new engine
- If the target is unsupported, it falls back to `default_target`
- Language code aliases are applied automatically (e.g. `EN` → `EN-US` for DeepL)

## Keymaps

| Keymap | Mode | Action | Default |
|---|---|---|---|
| `keymaps.translate_visual` | `x` | Translate visual selection | `<Space>tr` |
| `keymaps.select_target` | `n`, `x` | Open target language picker | `<Space>tl` |
| `keymaps.select_engine` | `n`, `x` | Open engine picker | `<Space>te` |

Set any keymap to `""` (empty string) to disable it.

## Commands

| Command | Description |
|---|---|
| `:TranslateSelectTarget` | Open target language picker for current engine |
| `:TranslateSelectEngine` | Switch translation engine (`deepl` / `google`) |

## Lua API

```lua
local translate = require("translate")

-- Setup with options (auto-called on plugin load)
translate.setup(opts?)

-- Translate current visual selection and show result in float
translate.translate_visual()

-- Open target language picker (vim.ui.select)
translate.select_target()

-- Open engine picker (vim.ui.select)
translate.select_engine()

-- Set target language programmatically
translate.set_target(code)       -- e.g. "EN", "JA", "KO"

-- Set engine programmatically
translate.set_engine(engine)     -- "deepl" or "google"

-- Query current state
translate.current_target()       -- returns e.g. "KO"
translate.current_engine()       -- returns e.g. "deepl"
```

## Health Check

```vim
:checkhealth translate
```

Checks: Neovim version (0.10+), `curl` availability, API key environment variables.

## Testing

Run the headless regression test suite:

```bash
nvim --headless -u NONE -i NONE "+set rtp+=." "+lua require('tests.headless.run_all').run()" "+qa!"
```

## License

MIT
