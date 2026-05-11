local ok_jdtls, jdtls = pcall(require, "jdtls")
if not ok_jdtls then
  return
end

local mason = vim.fn.stdpath("data") .. "/mason"
local root_dir = vim.fs.root(0, {
  "build.gradle", "build.gradle.kts", "pom.xml",
  "settings.gradle", "settings.gradle.kts", ".git",
}) or vim.fn.getcwd()

local project_name = vim.fn.fnamemodify(root_dir, ":p:h:t")
local workspace_dir = vim.fn.stdpath("data") .. "/jdtls-workspace/" .. project_name

local bundles = {
  vim.fn.glob(mason .. "/packages/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar", true),
}
vim.list_extend(
  bundles,
  vim.split(vim.fn.glob(mason .. "/packages/java-test/extension/server/*.jar", true), "\n")
)

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
  map("<leader>ci", function()
    vim.lsp.buf.code_action({
      context = {
        only = { "quickfix", "source" },
        diagnostics = vim.diagnostic.get(bufnr, { lnum = vim.fn.line(".") - 1 }),
      },
    })
  end, "Import / quickfix under cursor")
  map("<leader>cl", "<cmd>checkhealth vim.lsp<cr>", "LSP info")
  map("<leader>co", function() require("jdtls").organize_imports() end, "Organize imports")
  map("<leader>cv", function() require("jdtls").extract_variable() end, "Extract variable")
  map("<leader>cc", function() require("jdtls").extract_constant() end, "Extract constant")
  map("<leader>tn", function() require("jdtls").test_nearest_method() end, "Test nearest (jdtls)")
  map("<leader>tC", function() require("jdtls").test_class() end, "Test class (jdtls)")

  jdtls.setup_dap({ hotcodereplace = "auto" })
  require("jdtls.dap").setup_dap_main_class_configs()
end

local config = {
  cmd = { mason .. "/bin/jdtls", "-data", workspace_dir },
  root_dir = root_dir,
  capabilities = capabilities,
  on_attach = on_attach,
  settings = {
    java = {
      signatureHelp = { enabled = true },
      contentProvider = { preferred = "fernflower" },
      completion = {
        favoriteStaticMembers = {
          "org.junit.Assert.*",
          "org.junit.jupiter.api.Assertions.*",
          "org.mockito.Mockito.*",
        },
        filteredTypes = {
          "com.sun.*", "io.micrometer.shaded.*",
          "java.awt.*", "jdk.*", "sun.*",
        },
      },
      sources = {
        organizeImports = {
          starThreshold = 9999,
          staticStarThreshold = 9999,
        },
      },
      configuration = {
        runtimes = {
          {
            name = "JavaSE-21",
            path = vim.fn.expand("~/.local/share/mise/installs/java/21"),
          },
        },
      },
    },
  },
  init_options = {
    bundles = bundles,
  },
}

jdtls.start_or_attach(config)
