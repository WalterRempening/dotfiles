return {
  {
    "folke/tokyonight.nvim",
    priority = 1000,
    config = function()
      require("tokyonight").setup({
        transparent = true,
        styles = {
          sidebars = "transparent",
          floats = "dark",
        },
      })
      vim.cmd.colorscheme("tokyonight")
      vim.api.nvim_create_autocmd("ColorScheme", {
        callback = function()
          vim.api.nvim_set_hl(0, "LineNr", { fg = "#a0aac0" })
          vim.api.nvim_set_hl(0, "LineNrAbove", { fg = "#a0aac0" })
          vim.api.nvim_set_hl(0, "LineNrBelow", { fg = "#a0aac0" })
          vim.api.nvim_set_hl(0, "CursorLineNr", { fg = "#ff9e64", bold = true })
          vim.api.nvim_set_hl(0, "CursorLine", { bg = "NONE" })
          vim.api.nvim_set_hl(0, "MsgArea", { fg = "#e0e4f0" })
        end,
      })
      vim.api.nvim_set_hl(0, "LineNr", { fg = "#a0aac0" })
      vim.api.nvim_set_hl(0, "LineNrAbove", { fg = "#a0aac0" })
      vim.api.nvim_set_hl(0, "LineNrBelow", { fg = "#a0aac0" })
      vim.api.nvim_set_hl(0, "CursorLineNr", { fg = "#ff9e64", bold = true })
      vim.api.nvim_set_hl(0, "CursorLine", { bg = "NONE" })
      vim.api.nvim_set_hl(0, "MsgArea", { fg = "#e0e4f0" })
    end,
  },

  {
    "xiyaowong/transparent.nvim",
    lazy = false,
    opts = {
      extra_groups = {
        "NormalFloat",
        "FloatBorder",
        "TelescopeNormal",
        "TelescopeBorder",
        "TelescopePromptNormal",
        "TelescopePromptBorder",
      },
      exclude_groups = {
        "MasonNormal",
      },
    },
  },

  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
      local parsers = { "lua", "vim", "vimdoc", "c", "c_sharp", "java", "kotlin", "typescript", "tsx", "javascript", "html", "css", "json", "yaml", "markdown", "markdown_inline", "latex", "clojure", "edn", "swift" }
      for _, parser in ipairs(parsers) do
        pcall(function() vim.treesitter.language.add(parser) end)
      end
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(args)
          pcall(vim.treesitter.start, args.buf)
        end,
      })
    end,
  },

  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim", { "nvim-telescope/telescope-fzf-native.nvim", build = "make" } },
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find files" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Live grep" },
      { "<leader>fw", "<cmd>Telescope grep_string<cr>", desc = "Find word under cursor" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Buffers" },
      { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help tags" },
      { "<leader>fr", "<cmd>Telescope oldfiles<cr>", desc = "Recent files" },
      { "<leader>fk", "<cmd>Telescope keymaps<cr>", desc = "Keymaps" },
      { "<leader>fm", "<cmd>Telescope marks<cr>", desc = "Marks" },
      { "<leader>f:", "<cmd>Telescope command_history<cr>", desc = "Command history" },
      { "<leader>f/", "<cmd>Telescope search_history<cr>", desc = "Search history" },
      { "<leader>fc", "<cmd>Telescope git_commits<cr>", desc = "Git commits" },
      { "<leader>fs", "<cmd>Telescope git_status<cr>", desc = "Git status" },
      { "<leader>fB", "<cmd>Telescope git_branches<cr>", desc = "Git branches" },
      { "<leader>fd", "<cmd>Telescope diagnostics<cr>", desc = "Diagnostics" },
      { "<leader>ft", "<cmd>Telescope lsp_document_symbols<cr>", desc = "Document symbols" },
      { "<leader>fT", "<cmd>Telescope lsp_workspace_symbols<cr>", desc = "Workspace symbols" },
      { "<leader>fR", "<cmd>Telescope resume<cr>", desc = "Resume last search" },
      { "<leader>/", "<cmd>Telescope current_buffer_fuzzy_find<cr>", desc = "Search buffer" },
    },
    config = function()
      local telescope = require("telescope")
      local actions = require("telescope.actions")
      telescope.setup({
        defaults = { file_ignore_patterns = { "node_modules", ".git/" } },
        pickers = {
          find_files = { hidden = true },
          buffers = {
            sort_mru = true,
            mappings = {
              i = { ["<C-d>"] = actions.delete_buffer },
              n = { ["dd"] = actions.delete_buffer },
            },
          },
        },
      })
      telescope.load_extension("fzf")
    end,
  },

  {
    "stevearc/oil.nvim",
    lazy = false,
    dependencies = { "nvim-tree/nvim-web-devicons" },
    keys = {
      { "-", "<cmd>Oil<cr>", desc = "Open parent directory" },
      { "<leader>o", "<cmd>Oil<cr>", desc = "Oil file explorer" },
    },
    opts = {
      default_file_explorer = true,
      view_options = { show_hidden = true },
      keymaps = {
        ["g?"] = "actions.show_help",
        ["<CR>"] = "actions.select",
        ["<C-v>"] = "actions.select_vsplit",
        ["<C-s>"] = "actions.select_split",
        ["-"] = "actions.parent",
        ["_"] = "actions.open_cwd",
        ["g."] = "actions.toggle_hidden",
        ["q"] = "actions.close",
      },
    },
  },

  {
    "kdheepak/lazygit.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>gg", "<cmd>LazyGit<cr>", desc = "LazyGit" },
    },
  },

  {
    "lewis6991/gitsigns.nvim",
    opts = {
      signs = {
        add = { text = "│" },
        change = { text = "│" },
        delete = { text = "_" },
        topdelete = { text = "‾" },
        changedelete = { text = "~" },
      },
      on_attach = function(bufnr)
        local gs = require("gitsigns")
        local map = function(mode, l, r, opts)
          opts = opts or {}
          opts.buffer = bufnr
          vim.keymap.set(mode, l, r, opts)
        end
        map("n", "]h", gs.next_hunk, { desc = "Next hunk" })
        map("n", "[h", gs.prev_hunk, { desc = "Prev hunk" })
        map("n", "<leader>hs", gs.stage_hunk, { desc = "Stage hunk" })
        map("n", "<leader>hr", gs.reset_hunk, { desc = "Reset hunk" })
        map("n", "<leader>hp", gs.preview_hunk, { desc = "Preview hunk" })
        map("n", "<leader>hb", function() gs.blame_line({ full = true }) end, { desc = "Blame line" })
      end,
    },
  },

  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        theme = "tokyonight",
        component_separators = { left = "", right = "" },
        section_separators = { left = "", right = "" },
        globalstatus = true,
      },
      sections = {
        lualine_a = { "mode" },
        lualine_b = { "branch", "diff", "diagnostics" },
        lualine_c = { { "filename", path = 1 } },
        lualine_x = { "encoding", "fileformat", "filetype" },
        lualine_y = { "progress" },
        lualine_z = { "location" },
      },
    },
  },

  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
      "rafamadriz/friendly-snippets",
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")
      require("luasnip.loaders.from_vscode").lazy_load()

      local types = require("cmp.types")
      local kind_priority = {
        [types.lsp.CompletionItemKind.Field] = 1,
        [types.lsp.CompletionItemKind.Property] = 2,
        [types.lsp.CompletionItemKind.Method] = 3,
        [types.lsp.CompletionItemKind.Function] = 4,
        [types.lsp.CompletionItemKind.Variable] = 5,
        [types.lsp.CompletionItemKind.Constant] = 6,
        [types.lsp.CompletionItemKind.Class] = 7,
        [types.lsp.CompletionItemKind.Interface] = 8,
        [types.lsp.CompletionItemKind.Module] = 9,
        [types.lsp.CompletionItemKind.Keyword] = 10,
        [types.lsp.CompletionItemKind.Snippet] = 15,
        [types.lsp.CompletionItemKind.Text] = 20,
      }

      cmp.setup({
        snippet = {
          expand = function(args) luasnip.lsp_expand(args.body) end,
        },
        completion = { completeopt = "menu,menuone,noinsert" },
        sorting = {
          priority_weight = 2,
          comparators = {
            cmp.config.compare.exact,
            function(entry1, entry2)
              local kind1 = kind_priority[entry1:get_kind()] or 100
              local kind2 = kind_priority[entry2:get_kind()] or 100
              if kind1 ~= kind2 then
                return kind1 < kind2
              end
            end,
            cmp.config.compare.score,
            cmp.config.compare.recently_used,
            cmp.config.compare.locality,
            cmp.config.compare.order,
          },
        },
        mapping = {
          ["<C-n>"] = cmp.mapping.select_next_item(),
          ["<C-p>"] = cmp.mapping.select_prev_item(),
          ["<C-y>"] = cmp.mapping.confirm({ select = true }),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
        },
        sources = {
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "buffer" },
          { name = "path" },
        },
      })

      cmp.setup.filetype({ "sql", "mysql", "plsql" }, {
        sources = {
          { name = "vim-dadbod-completion" },
          { name = "buffer" },
        },
      })
    end,
  },

  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    keys = {
      { "<leader>cf", function() require("conform").format({ async = true }) end, desc = "Format buffer" },
    },
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
        javascript = { "prettier" },
        typescript = { "prettier" },
        javascriptreact = { "prettier" },
        typescriptreact = { "prettier" },
        json = { "prettier" },
        html = { "prettier" },
        css = { "prettier" },
        java = { "google-java-format" },
        swift = { "swift_format" },
        -- kotlin uses LSP formatting (ktlint has stdin bugs)
        go = { "goimports", "gofumpt" },
        c = { "clang-format" },
        cpp = { "clang-format" },
        cs = { "csharpier" },
      },
      format_on_save = { timeout_ms = 500, lsp_fallback = true },
    },
  },

  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      local lint = require("lint")
      lint.linters_by_ft = {
        javascript = { "eslint_d" },
        typescript = { "eslint_d" },
        javascriptreact = { "eslint_d" },
        typescriptreact = { "eslint_d" },
      }
      vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
        callback = function() lint.try_lint() end,
      })
    end,
  },

  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "rcarriga/nvim-dap-ui",
      "nvim-neotest/nvim-nio",
      "theHamsta/nvim-dap-virtual-text",
    },
    keys = {
      { "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "Toggle breakpoint" },
      { "<leader>dc", function() require("dap").continue() end, desc = "Continue" },
      { "<leader>di", function() require("dap").step_into() end, desc = "Step into" },
      { "<leader>do", function() require("dap").step_over() end, desc = "Step over" },
      { "<leader>dO", function() require("dap").step_out() end, desc = "Step out" },
      { "<leader>dr", function() require("dap").repl.open() end, desc = "Open REPL" },
      { "<leader>du", function() require("dapui").toggle() end, desc = "Toggle DAP UI" },
    },
    config = function()
      local dap = require("dap")
      local dapui = require("dapui")

      dapui.setup()
      require("nvim-dap-virtual-text").setup()

      dap.listeners.after.event_initialized["dapui_config"] = function() dapui.open() end
      dap.listeners.before.event_terminated["dapui_config"] = function() dapui.close() end
      dap.listeners.before.event_exited["dapui_config"] = function() dapui.close() end

      dap.adapters["pwa-node"] = {
        type = "server",
        host = "localhost",
        port = "${port}",
        executable = {
          command = "node",
          args = { vim.fn.stdpath("data") .. "/mason/packages/js-debug-adapter/js-debug/src/dapDebugServer.js", "${port}" },
        },
      }

      for _, lang in ipairs({ "typescript", "javascript", "typescriptreact", "javascriptreact" }) do
        dap.configurations[lang] = {
          { type = "pwa-node", request = "launch", name = "Launch file", program = "${file}", cwd = "${workspaceFolder}" },
          { type = "pwa-node", request = "attach", name = "Attach", processId = require("dap.utils").pick_process, cwd = "${workspaceFolder}" },
        }
      end

      dap.adapters.codelldb = {
        type = "server",
        port = "${port}",
        executable = { command = vim.fn.stdpath("data") .. "/mason/bin/codelldb", args = { "--port", "${port}" } },
      }

      for _, lang in ipairs({ "c", "cpp" }) do
        dap.configurations[lang] = {
          { type = "codelldb", request = "launch", name = "Launch", program = function() return vim.fn.input("Executable: ", vim.fn.getcwd() .. "/", "file") end, cwd = "${workspaceFolder}" },
        }
      end

      dap.adapters.kotlin = { type = "executable", command = vim.fn.stdpath("data") .. "/mason/bin/kotlin-debug-adapter" }
      dap.configurations.kotlin = {
        { type = "kotlin", request = "launch", name = "Launch Kotlin", projectRoot = "${workspaceFolder}", mainClass = function() return vim.fn.input("Main class: ") end },
      }
    end,
  },

  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-neotest/nvim-nio",
      "antoinemadec/FixCursorHold.nvim",
      "nvim-treesitter/nvim-treesitter",
      "weilbith/neotest-gradle",
      "fredrikaverpil/neotest-golang",
    },
    keys = {
      { "<leader>tt", function() require("neotest").run.run() end, desc = "Run nearest test" },
      { "<leader>tf", function() require("neotest").run.run(vim.fn.expand("%")) end, desc = "Run file tests" },
      { "<leader>tl", function() require("neotest").run.run_last() end, desc = "Run last test" },
      { "<leader>td", function() require("neotest").run.run({ strategy = "dap" }) end, desc = "Debug nearest test" },
      { "<leader>ts", function() require("neotest").summary.toggle() end, desc = "Toggle test summary" },
      { "<leader>to", function() require("neotest").output.open({ enter = true }) end, desc = "Show test output" },
      { "<leader>tp", function() require("neotest").output_panel.toggle() end, desc = "Toggle output panel" },
      { "<leader>tx", function() require("neotest").run.stop() end, desc = "Stop test" },
    },
    config = function()
      require("neotest").setup({
        adapters = {
          require("neotest-gradle"),
          require("neotest-golang")({
            dap_go_enabled = true,
          }),
        },
      })
    end,
  },

  {
    "stevearc/overseer.nvim",
    keys = {
      { "<leader>rr", "<cmd>OverseerRun<cr>", desc = "Run task" },
      { "<leader>rt", "<cmd>OverseerToggle<cr>", desc = "Toggle task list" },
      { "<leader>ra", "<cmd>OverseerQuickAction<cr>", desc = "Task quick action" },
      { "<leader>ri", "<cmd>OverseerInfo<cr>", desc = "Overseer info" },
      { "<leader>rb", "<cmd>OverseerBuild<cr>", desc = "Build task" },
    },
    opts = {
      templates = { "builtin", "user.gradle_build", "user.gradle_test" },
    },
  },

  {
    "mason-org/mason.nvim",
    build = ":MasonUpdate",
    opts = {},
  },

  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "mason-org/mason.nvim" },
    event = "VeryLazy",
    opts = {
      ensure_installed = {
        -- LSPs (go tools live in mise)
        "typescript-language-server",
        "jdtls",
        "lua-language-server",
        "clojure-lsp",
        -- DAP adapters
        "kotlin-debug-adapter",
        "js-debug-adapter",
        "codelldb",
        "java-debug-adapter",
        "java-test",
        -- Formatters
        "stylua",
        "prettier",
        "google-java-format",
        "clang-format",
        "csharpier",
        -- Linters
        "eslint_d",
      },
      auto_update = false,
      run_on_start = true,
    },
  },

  {
    "leoluz/nvim-dap-go",
    ft = "go",
    dependencies = { "mfussenegger/nvim-dap" },
    opts = {},
  },

  {
    "mfussenegger/nvim-jdtls",
    ft = "java",
    dependencies = { "mfussenegger/nvim-dap" },
  },

  {
    "kylechui/nvim-surround",
    event = "VeryLazy",
    opts = {},
  },

  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    dependencies = { "hrsh7th/nvim-cmp" },
    config = function()
      local autopairs = require("nvim-autopairs")
      autopairs.setup({
        check_ts = true,
        ts_config = {
          lua = { "string" },
          javascript = { "template_string" },
        },
      })
      local cmp_autopairs = require("nvim-autopairs.completion.cmp")
      require("cmp").event:on("confirm_done", cmp_autopairs.on_confirm_done())
    end,
  },

  {
    "kristijanhusak/vim-dadbod-ui",
    dependencies = {
      { "tpope/vim-dadbod", lazy = true },
      { "kristijanhusak/vim-dadbod-completion", ft = { "sql", "mysql", "plsql" }, lazy = true },
    },
    cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" },
    keys = {
      { "<leader>D", "<cmd>DBUIToggle<cr>", desc = "Toggle DBUI" },
    },
    init = function()
      vim.g.db_ui_use_nerd_fonts = 1
    end,
  },

  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "modern",
      delay = 300,
      win = {
        width = 35,
        col = vim.o.columns,
        border = "rounded",
      },
      layout = {
        align = "left",
      },
      spec = {
        { "<leader>f", group = "find" },
        { "<leader>g", group = "git" },
        { "<leader>h", group = "hunks" },
        { "<leader>c", group = "code" },
        { "<leader>d", group = "debug" },
        { "<leader>l", group = "latex" },
        { "<leader>t", group = "test" },
        { "<leader>r", group = "run/tasks" },
        { "<leader>b", group = "buffers" },
      },
    },
  },

  {
    "Olical/conjure",
    ft = { "clojure", "fennel", "scheme" },
    init = function()
      vim.g["conjure#mapping#prefix"] = "<localleader>"
      vim.g["conjure#filetype#scheme"] = false
      vim.g["conjure#client#clojure#nrepl#eval#auto_require"] = true
      vim.g["conjure#client#clojure#nrepl#connection#auto_repl#enabled"] = false
    end,
  },

  {
    "guns/vim-sexp",
    ft = { "clojure", "lisp", "scheme" },
    dependencies = { "tpope/vim-sexp-mappings-for-regular-people" },
  },

  { import = "plugins.lsp" },
}
