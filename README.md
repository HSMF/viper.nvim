# viper.nvim

Neovim plugin for the [Viper verification language](https://viper.ethz.ch/), powered by ViperServer.

## Requirements

- Neovim ≥ 0.12
- `viperserver` on `$PATH` (wraps the Java server)
- `silicon` or `carbon` backend on `$PATH`

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "HSMF/viper.nvim",
  ft = "viper",
  opts = {},
}
```

Or call setup manually:

```lua
require("viper").setup({
  backend     = "silicon",   -- "silicon" | "carbon"
  auto_verify = true,        -- verify on save
  log_level   = "INFO",      -- OFF ERROR INFO DEBUG TRACE ALL
  custom_args = "",          -- extra args forwarded to verifier
})
```

## Features

| Feature | How |
|---|---|
| Auto-start ViperServer | Opens on first `.vpr`/`.sil` file |
| Auto-verify | On `BufWritePost` (disable with `auto_verify = false`) |
| Manual verify | `:Verify` command |
| Diagnostics | Errors/warnings in quickfix via LSP |
| Syntax highlighting | `syntax/viper.vim` + LSP semantic tokens |
| Document highlight | Symbol under cursor highlighted via `textDocument/documentHighlight` |
| Standard LSP | Hover, go-to-definition, etc. if ViperServer supports them |

## How it works

1. On first `.vpr`/`.sil` buffer, spawns `viperserver --serverMode LSP --singleClient`.
2. Reads stdout for `<ViperServerPort:N>`, connects via TCP.
3. Performs `GetVersion` handshake.
4. Sends `Verify` notification on save (or `:Verify`).
5. `StateChange` notifications drive status messages and diagnostics.
6. `textDocument/documentHighlight` fires on `CursorHold`.
