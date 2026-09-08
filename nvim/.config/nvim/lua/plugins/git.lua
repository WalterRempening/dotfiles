return {
  {
    -- `:Flog` is what the shell aliases `vil` / `vilu` invoke. It had been left
    -- out of this config, so those aliases opened nvim and died with
    -- "E492: Not an editor command: Flog".
    "rbong/vim-flog",
    -- flog is a layer on top of fugitive and won't start without it.
    dependencies = { "tpope/vim-fugitive" },
    cmd = { "Flog", "Flogsplit", "Floggit" },
  },

  {
    -- Comes in as a flog dependency, but that only loads it when `:Flog` runs.
    -- With its own cmd list, `:Git blame`, `:Gdiffsplit` (three-way conflict
    -- resolution) and friends are available on their own.
    "tpope/vim-fugitive",
    cmd = { "Git", "G", "Gdiffsplit", "Gvdiffsplit", "Gread", "Gwrite", "Gedit", "Gclog", "GBrowse" },
  },
}
