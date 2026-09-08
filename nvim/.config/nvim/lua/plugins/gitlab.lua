return {
  {
    -- Configures the fork that gitlab.nvim pulls in as a dependency below.
    -- `main` is spelled out because lazy guesses the module from the repo
    -- name, and "diffview-plus.nvim" normalises to "diffviewplus" while the
    -- module is plain "diffview".
    --
    -- NO diff1_inline here, however tempting. The fork's unified diff is a
    -- single-window layout, and gitlab.nvim needs two: it reads
    -- `cur_layout.a.file.path` when it paints comment indicators
    -- (indicators/diagnostics.lua:140) and `cur_layout.a.file.bufnr` when it
    -- works out which side a new comment belongs to (reviewer/init.lua:215).
    -- A `Diff1` has only `.b`, so cycling to inline inside a review turns
    -- every <tab> to the next file into an "attempt to index field 'a'"
    -- error storm. Upstream has no notion of the layout at all.
    --
    -- The stock cycle is left alone (diff2_horizontal <-> diff2_vertical).
    -- For a unified diff of ordinary work — outside a GitLab review, where
    -- nothing indexes `.a` — open `:DiffviewOpen` and pick the layout there
    -- with `:DiffviewOpen -- --imply-local` + g<C-x>, or set it per-call.
    "dlyongemallo/diffview-plus.nvim",
    main = "diffview",
  },
  {
    "harrisoncramer/gitlab.nvim",
    dependencies = {
      "MunifTanjim/nui.nvim",
      -- Maintained fork of sindrets/diffview.nvim. gitlab.nvim itself recommends
      -- it: it detects renamed files with the same similarity threshold GitLab
      -- uses (30%), and without that a comment on a renamed file is stored with
      -- the wrong metadata or fails to send.
      "dlyongemallo/diffview-plus.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    config = function()
      -- The token can NOT come from glab. `glab auth login` through the browser
      -- stores an OAuth token (64 hex chars, no glpat- prefix), and this
      -- plugin's Go server uses gitlab.NewClient(), which sends the
      -- PRIVATE-TOKEN header. That header only accepts PATs: with the OAuth
      -- token the API answers 401 (the same token works with
      -- Authorization: Bearer, but the plugin offers no such option). So this
      -- needs a real PAT with the `api` scope.
      --
      -- It lives in the macOS keychain rather than a file: nothing in plain
      -- text, and it doesn't depend on the shell exporting anything.
      --   security add-generic-password -a "$USER" -s gitlab-nvim-token -U -w <token>
      local token

      require("gitlab").setup({
        auth_provider = function()
          if token == nil then
            local out = vim.system({
              "security",
              "find-generic-password",
              "-s",
              "gitlab-nvim-token",
              "-w",
            }):wait()
            token = out.code == 0 and vim.trim(out.stdout or "") or ""
            -- Fallback in case you'd rather export it from the shell.
            if token == "" then
              token = vim.trim(vim.env.GITLAB_TOKEN or "")
            end
            -- A pipeline like `jq -r .token` over an error response stores the
            -- string "null" and exits 0; sending that would produce a 401 that
            -- looks like a permissions problem instead of a missing token.
            if token == "null" then
              token = ""
            end
          end
          if token == "" then
            return nil,
              nil,
              "no GitLab PAT: create one with the `api` scope and store it with "
                .. '`security add-generic-password -a "$USER" -s gitlab-nvim-token -U -w <token>`'
          end
          -- gitlab_url nil => https://gitlab.com
          return token, nil, nil
        end,
      })
    end,
  },
}
