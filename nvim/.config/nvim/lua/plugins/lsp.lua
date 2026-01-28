return {
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "hrsh7th/cmp-nvim-lsp" },
    config = function()
      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      local on_attach = function(client, bufnr)
        local map = function(keys, func, desc)
          vim.keymap.set("n", keys, func, { buffer = bufnr, desc = desc })
        end
        map("gd", vim.lsp.buf.definition, "Go to definition")
        map("gD", vim.lsp.buf.declaration, "Go to declaration")
        map("gi", vim.lsp.buf.implementation, "Go to implementation")
        map("gr", vim.lsp.buf.references, "Go to references")
        map("gt", vim.lsp.buf.type_definition, "Go to type definition")
        map("K", vim.lsp.buf.hover, "Hover documentation")
        map("<leader>cr", vim.lsp.buf.rename, "Rename symbol")
        map("<leader>ca", vim.lsp.buf.code_action, "Code action")
        map("<leader>cl", "<cmd>checkhealth lsp<cr>", "LSP info")
      end

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "lua",
        callback = function(args)
          vim.lsp.start({
            name = "lua_ls",
            cmd = { "lua-language-server" },
            root_dir = vim.fs.root(args.buf, { ".luarc.json", ".luarc.jsonc", ".stylua.toml", "stylua.toml", ".git" }) or vim.fn.getcwd(),
            capabilities = capabilities,
            on_attach = on_attach,
            settings = {
              Lua = {
                runtime = { version = "LuaJIT" },
                workspace = { checkThirdParty = false, library = { vim.env.VIMRUNTIME } },
                completion = { callSnippet = "Replace" },
              },
            },
          })
        end,
      })

      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "c", "cpp" },
        callback = function(args)
          vim.lsp.start({
            name = "clangd",
            cmd = { "clangd", "--background-index", "--clang-tidy", "--header-insertion=iwyu" },
            root_dir = vim.fs.root(args.buf, { "compile_commands.json", "compile_flags.txt", "Makefile", ".git" }) or vim.fn.getcwd(),
            capabilities = capabilities,
            on_attach = on_attach,
          })
        end,
      })

      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
        callback = function(args)
          vim.lsp.start({
            name = "ts_ls",
            cmd = { "typescript-language-server", "--stdio" },
            root_dir = vim.fs.root(args.buf, { "tsconfig.json", "jsconfig.json", "package.json", ".git" }) or vim.fn.getcwd(),
            capabilities = capabilities,
            on_attach = on_attach,
            init_options = { hostInfo = "neovim" },
          })
        end,
      })

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "java",
        callback = function(args)
          local root_dir = vim.fs.root(args.buf, { "build.gradle", "build.gradle.kts", "pom.xml", "settings.gradle", "settings.gradle.kts", ".git" }) or vim.fn.getcwd()
          local project_name = vim.fn.fnamemodify(root_dir, ":p:h:t")
          local workspace_dir = vim.fn.stdpath("data") .. "/jdtls-workspace/" .. project_name

          vim.lsp.start({
            name = "jdtls",
            cmd = {
              vim.fn.stdpath("data") .. "/mason/bin/jdtls",
              "-data", workspace_dir,
            },
            root_dir = root_dir,
            capabilities = capabilities,
            on_attach = on_attach,
            single_file_support = true,
            settings = {
              java = {
                signatureHelp = { enabled = true },
                completion = {
                  favoriteStaticMembers = {
                    "org.junit.Assert.*",
                    "org.junit.jupiter.api.Assertions.*",
                    "org.mockito.Mockito.*",
                  },
                  filteredTypes = {
                    "com.sun.*",
                    "io.micrometer.shaded.*",
                    "java.awt.*",
                    "jdk.*",
                    "sun.*",
                  },
                },
                sources = {
                  organizeImports = {
                    starThreshold = 9999,
                    staticStarThreshold = 9999,
                  },
                },
              },
            },
            init_options = {
              bundles = {},
            },
          })
        end,
      })

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "kotlin",
        callback = function(args)
          vim.lsp.start({
            name = "kotlin_language_server",
            cmd = { vim.fn.stdpath("data") .. "/mason/bin/kotlin-language-server" },
            root_dir = vim.fs.root(args.buf, { "build.gradle", "build.gradle.kts", "pom.xml", "settings.gradle", "settings.gradle.kts", ".git" }) or vim.fn.getcwd(),
            capabilities = capabilities,
            on_attach = on_attach,
            single_file_support = true,
            cmd_env = {
              JAVA_HOME = vim.fn.expand("~/.local/share/mise/installs/java/21"),
              JAVA_OPTS = "-Xmx4g",
            },
            settings = {
              kotlin = {
                compiler = { jvm = { target = "21" } },
              },
            },
          })
        end,
      })

      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "tex", "plaintex", "bib" },
        callback = function(args)
          vim.lsp.start({
            name = "texlab",
            cmd = { "texlab" },
            root_dir = vim.fs.root(args.buf, { ".latexmkrc", "latexmkrc", ".git" }) or vim.fn.getcwd(),
            capabilities = capabilities,
            settings = {
              texlab = {
                build = {
                  executable = "/Library/TeX/texbin/xelatex",
                  args = { "-interaction=nonstopmode", "-synctex=1", "%f" },
                  onSave = false,
                },
                forwardSearch = {
                  executable = "/Applications/Skim.app/Contents/SharedSupport/displayline",
                  args = { "-g", "%l", "%p", "%f" },
                },
              },
            },
            on_attach = function(client, bufnr)
              on_attach(client, bufnr)
              local map = function(keys, func, desc)
                vim.keymap.set("n", keys, func, { buffer = bufnr, desc = desc })
              end
              map("<leader>lb", function()
                local uri = vim.uri_from_bufnr(bufnr)
                local tex = vim.api.nvim_buf_get_name(bufnr)
                local pdf = tex:gsub("%.tex$", ".pdf")
                local line = vim.api.nvim_win_get_cursor(0)[1]
                client:request("textDocument/build", { textDocument = { uri = uri } }, function(err, result)
                  vim.schedule(function()
                    if err then
                      vim.notify("Build error: " .. vim.inspect(err), vim.log.levels.ERROR)
                      return
                    end
                    -- status: 0=success, 1=error (PDF may exist), 2=failure, 3=cancelled
                    if result and result.status <= 1 and vim.fn.filereadable(pdf) == 1 then
                      if result.status == 1 then
                        vim.notify("Build completed with warnings", vim.log.levels.WARN)
                      else
                        vim.notify("Build successful", vim.log.levels.INFO)
                      end
                      vim.fn.jobstart({ "/Applications/Skim.app/Contents/SharedSupport/displayline", "-r", tostring(line), pdf, tex })
                    else
                      vim.notify("Build failed (status " .. (result and result.status or "nil") .. ")", vim.log.levels.ERROR)
                    end
                  end)
                end, bufnr)
              end, "Build document")
              map("<leader>lf", function()
                local uri = vim.uri_from_bufnr(bufnr)
                local pos = vim.api.nvim_win_get_cursor(0)
                client:request("textDocument/forwardSearch", {
                  textDocument = { uri = uri },
                  position = { line = pos[1] - 1, character = pos[2] },
                }, nil, bufnr)
              end, "Forward search")
              map("<leader>lc", function()
                local dir = vim.fn.expand("%:p:h")
                local base = vim.fn.expand("%:t:r")
                local aux_files = { ".aux", ".log", ".out", ".toc", ".fls", ".fdb_latexmk", ".synctex.gz" }
                for _, ext in ipairs(aux_files) do
                  os.remove(dir .. "/" .. base .. ext)
                end
                vim.notify("Cleaned auxiliary files", vim.log.levels.INFO)
              end, "Clean auxiliary files")
              map("<leader>lC", function()
                local dir = vim.fn.expand("%:p:h")
                local base = vim.fn.expand("%:t:r")
                local all_files = { ".aux", ".log", ".out", ".toc", ".fls", ".fdb_latexmk", ".synctex.gz", ".pdf" }
                for _, ext in ipairs(all_files) do
                  os.remove(dir .. "/" .. base .. ext)
                end
                vim.notify("Cleaned all artifacts", vim.log.levels.INFO)
              end, "Clean all artifacts")
              -- Watch mode: auto-build on save
              local watch_group = vim.api.nvim_create_augroup("TexlabWatch_" .. bufnr, { clear = true })
              local watch_autocmd_id = nil
              map("<leader>lw", function()
                if watch_autocmd_id then
                  vim.api.nvim_del_autocmd(watch_autocmd_id)
                  watch_autocmd_id = nil
                  vim.notify("Watch mode OFF", vim.log.levels.INFO)
                else
                  local filepath = vim.api.nvim_buf_get_name(bufnr)
                  local pdf = filepath:gsub("%.tex$", ".pdf")
                  watch_autocmd_id = vim.api.nvim_create_autocmd("BufWritePost", {
                    group = watch_group,
                    buffer = bufnr,
                    callback = function()
                      local uri = vim.uri_from_fname(filepath)
                      client:request("textDocument/build", { textDocument = { uri = uri } }, function(err, result)
                        vim.schedule(function()
                          if result and result.status <= 1 and vim.fn.filereadable(pdf) == 1 then
                            vim.fn.jobstart({ "/Applications/Skim.app/Contents/SharedSupport/displayline", "-r", "-b", "1", pdf, filepath })
                          end
                        end)
                      end, bufnr)
                    end,
                  })
                  vim.notify("Watch mode ON - auto-build on save", vim.log.levels.INFO)
                end
              end, "Toggle watch mode")
            end,
          })
        end,
      })

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "cs",
        callback = function(args)
          vim.lsp.start({
            name = "omnisharp",
            cmd = { "omnisharp", "--languageserver", "--hostPID", tostring(vim.fn.getpid()) },
            root_dir = vim.fs.root(args.buf, { "*.sln", "*.csproj", ".git" }) or vim.fn.getcwd(),
            capabilities = capabilities,
            on_attach = on_attach,
            settings = {
              FormattingOptions = {
                EnableEditorConfigSupport = true,
                OrganizeImports = true,
              },
              RoslynExtensionsOptions = {
                EnableAnalyzersSupport = true,
                EnableImportCompletion = true,
              },
            },
          })
        end,
      })
    end,
  },
}
