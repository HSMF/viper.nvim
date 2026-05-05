# viper.nvim

Neovim plugin for the [Viper verification language](https://www.pm.inf.ethz.ch/research/viper.html), powered by [viperserver](https://github.com/viperproject/viperserver).

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "HSMF/viper.nvim",
  ft = "viper",
  opts = {},
}
```

Or using `vim.pack.add`

```lua
vim.pack.add({ "https://github.com/HSMF/viper.nvim" })
require("viper").setup({
    backend     = "silicon", -- "silicon" | "carbon"
    auto_verify = true,      -- verify on save
    log_level   = "INFO",    -- OFF ERROR INFO DEBUG TRACE ALL
    custom_args = "",        -- extra args forwarded to verifier
})
```
