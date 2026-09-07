return {
  {
    "harrisoncramer/gitlab.nvim",
    dependencies = {
      "MunifTanjim/nui.nvim",
      -- Fork mantenido de sindrets/diffview.nvim. El propio gitlab.nvim lo
      -- recomienda: detecta archivos renombrados con el mismo umbral que usa
      -- GitLab (30%), y sin eso un comentario sobre un archivo renombrado se
      -- guarda con metadatos equivocados o falla al enviarse.
      "dlyongemallo/diffview-plus.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    config = function()
      -- El token NO puede salir de glab. `glab auth login` por navegador guarda
      -- un token OAuth (64 hex, sin prefijo glpat-), y el servidor Go de este
      -- plugin usa gitlab.NewClient(), que manda el header PRIVATE-TOKEN. Ese
      -- header solo acepta PATs: con el OAuth, la API contesta 401 (con
      -- Authorization: Bearer el mismo token da 200, pero el plugin no ofrece
      -- esa opción). Hace falta un PAT propio con scope `api`.
      --
      -- Se guarda en el llavero de macOS en vez de un archivo: nada en texto
      -- plano, y no depende de que la shell exporte nada.
      --   security add-generic-password -a "$USER" -s gitlab-nvim-token -w -U
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
            -- Respaldo por si prefieres exportarlo en la shell.
            if token == "" then
              token = vim.trim(vim.env.GITLAB_TOKEN or "")
            end
            -- Un pipeline con `jq -r .token` sobre una respuesta de error guarda
            -- la cadena "null" y sale con código 0; mandarla daría un 401 que
            -- parece problema de permisos y no de token faltante.
            if token == "null" then
              token = ""
            end
          end
          if token == "" then
            return nil,
              nil,
              "sin PAT de GitLab: crea uno con scope `api` y guárdalo con "
                .. '`security add-generic-password -a "$USER" -s gitlab-nvim-token -w -U`'
          end
          -- gitlab_url nil => https://gitlab.com
          return token, nil, nil
        end,
      })
    end,
  },
}
