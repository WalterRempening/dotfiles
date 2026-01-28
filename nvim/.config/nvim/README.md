# Neovim Configuration

Minimal, modern Neovim config for Neovim 0.11+ using native LSP APIs.

## Structure

```
~/.config/nvim/
├── init.lua                 # Entry point: leader keys, lazy.nvim bootstrap
├── lua/
│   ├── config/
│   │   ├── options.lua      # Vim options (tabs, numbers, etc.)
│   │   ├── keymaps.lua      # Global keybindings
│   │   └── autocmds.lua     # Autocommands (yank highlight, restore cursor, etc.)
│   └── plugins/
│       ├── init.lua         # All plugin specs (telescope, oil, git, completion, etc.)
│       └── lsp.lua          # LSP configurations for all languages
```

## Language Support

| Language | LSP | Formatter | Linter |
|----------|-----|-----------|--------|
| Lua | lua_ls | stylua | - |
| C/C++ | clangd | clang-format | clangd |
| Java | jdtls | google-java-format | jdtls |
| Kotlin | kotlin_language_server | ktlint | ktlint |
| TypeScript/React | ts_ls | prettier | eslint_d |
| LaTeX | texlab | - | - |
| JTE/KTE | - (HTML fallback) | - | - |

## Keybindings

### General
| Key | Action |
|-----|--------|
| `<Space>` | Leader key |
| `<Esc>` | Clear search highlight |
| `<leader>w` | Save file |
| `<leader>W` | Save all files |
| `<C-h/j/k/l>` | Navigate windows |

### File Navigation
| Key | Action |
|-----|--------|
| `-` | Open Oil (file explorer) |
| `<leader>o` | Open Oil |
| `<leader>ff` | Find files (Telescope) |
| `<leader>fg` | Live grep |
| `<leader>fb` | Buffers |
| `<leader>fr` | Recent files |
| `<leader>/` | Search in buffer |

### Git
| Key | Action |
|-----|--------|
| `<leader>gg` | Open LazyGit |
| `<leader>fc` | Git commits (Telescope) |
| `<leader>fs` | Git status (Telescope) |
| `]h` / `[h` | Next/prev hunk |
| `<leader>hs` | Stage hunk |
| `<leader>hr` | Reset hunk |
| `<leader>hp` | Preview hunk |
| `<leader>hb` | Blame line |

### LSP
| Key | Action |
|-----|--------|
| `gd` | Go to definition |
| `gD` | Go to declaration |
| `gi` | Go to implementation |
| `gr` | Go to references |
| `gt` | Go to type definition |
| `K` | Hover documentation |
| `<leader>cr` | Rename symbol |
| `<leader>ca` | Code action |
| `<leader>cf` | Format buffer |
| `<leader>cl` | LSP health check |

### Diagnostics
| Key | Action |
|-----|--------|
| `[d` / `]d` | Prev/next diagnostic |
| `<leader>e` | Show diagnostic float |
| `<leader>q` | Diagnostic list |

### Completion (nvim-cmp)
| Key | Action |
|-----|--------|
| `<C-n>` / `<Tab>` | Next item |
| `<C-p>` / `<S-Tab>` | Previous item |
| `<C-y>` | Confirm selection |
| `<C-Space>` | Trigger completion |
| `<C-b>` / `<C-f>` | Scroll docs |

### Debugging (DAP)
| Key | Action |
|-----|--------|
| `<leader>db` | Toggle breakpoint |
| `<leader>dc` | Continue |
| `<leader>di` | Step into |
| `<leader>do` | Step over |
| `<leader>dO` | Step out |
| `<leader>dr` | Open REPL |
| `<leader>du` | Toggle DAP UI |

## Adding a New Language

1. **LSP**: Add an autocmd in `lua/plugins/lsp.lua`:
```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = "your_filetype",
  callback = function(args)
    vim.lsp.start({
      name = "your_lsp_name",
      cmd = { "your-lsp-command" },
      root_dir = vim.fs.root(args.buf, { "marker_file", ".git" }) or vim.fn.getcwd(),
      capabilities = capabilities,
      on_attach = on_attach,
    })
  end,
})
```

2. **Formatter**: Add to `formatters_by_ft` in `lua/plugins/init.lua` (conform.nvim section)

3. **Linter**: Add to `linters_by_ft` in `lua/plugins/init.lua` (nvim-lint section)

4. **Treesitter**: Add the parser to `ensure_installed` in the treesitter config

## Adding a New Plugin

Add to `lua/plugins/init.lua`:
```lua
{
  "author/plugin-name",
  event = "VeryLazy",  -- optional: lazy load on event
  keys = {             -- optional: lazy load on keymap
    { "<leader>x", "<cmd>PluginCommand<cr>", desc = "Description" },
  },
  opts = {},           -- plugin options
},
```

## Mason (Tool Installation)

Mason manages LSP servers, formatters, linters, and debug adapters.

```vim
:Mason              " Open Mason UI
:MasonInstall xxx   " Install a tool
:MasonUpdate        " Update all tools
```

Required tools (install via Mason):
- `lua-language-server`
- `clangd`
- `jdtls`
- `kotlin-language-server`
- `typescript-language-server`
- `texlab`
- `stylua`
- `prettier`
- `google-java-format`
- `ktlint`
- `clang-format`
- `eslint_d`
- `js-debug-adapter`
- `codelldb`
- `kotlin-debug-adapter`

## Customization

### Change colorscheme
Edit `lua/plugins/init.lua`, first line:
```lua
{ "folke/tokyonight.nvim", priority = 1000, config = function() vim.cmd.colorscheme("tokyonight") end },
```

### Change options
Edit `lua/config/options.lua`

### Add keymaps
Edit `lua/config/keymaps.lua`

### Kotlin Java version
Edit `lua/plugins/lsp.lua`, find `kotlin_language_server` section and change:
```lua
JAVA_HOME = vim.fn.expand("~/.local/share/mise/installs/java/21"),
```

## Troubleshooting

### LSP not starting
1. Check if the server is installed: `:Mason`
2. Check LSP health: `:checkhealth lsp`
3. Check LSP log: `:lua vim.cmd('edit ' .. vim.lsp.get_log_path())`

### Formatting not working
1. Check conform info: `:ConformInfo`
2. Ensure formatter is installed via Mason

### Plugin issues
1. Update plugins: `:Lazy update`
2. Check lazy health: `:checkhealth lazy`
3. Clean and reinstall: `:Lazy clean` then restart

## Requirements

- Neovim 0.11+
- Git
- A Nerd Font (for icons)
- ripgrep (for Telescope live grep)
- Node.js (for TypeScript LSP)
- Java 21 (for Kotlin LSP)
