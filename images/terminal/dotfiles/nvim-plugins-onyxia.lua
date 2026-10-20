-- Ajouts de l'image aux plugins de LazyVim (copié dans lua/plugins/onyxia.lua).

-- Fichiers cachés (.github, .gitignore…) visibles par défaut dans l'explorateur
-- (Espace e) et les recherches de fichiers / texte ; H (Alt+h dans une
-- recherche) pour basculer. Les fichiers ignorés par git restent masqués (I).
return {
  "folke/snacks.nvim",
  opts = {
    picker = {
      sources = {
        explorer = { hidden = true },
        files = { hidden = true },
        grep = { hidden = true },
      },
    },
  },
}
