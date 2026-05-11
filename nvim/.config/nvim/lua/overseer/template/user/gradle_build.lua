return {
  name = "gradle build",
  builder = function()
    return {
      cmd = { "./gradlew" },
      args = { "build" },
      components = { { "on_output_quickfix", open = true }, "default" },
    }
  end,
  condition = {
    callback = function(opts)
      return vim.fn.filereadable(opts.dir .. "/gradlew") == 1
    end,
  },
}
