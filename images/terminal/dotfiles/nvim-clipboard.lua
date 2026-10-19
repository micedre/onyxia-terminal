
-- Presse-papiers (ajout de l'image) : la copie part en OSC 52 vers tmux puis le
-- navigateur ; le collage lit le registre courant (le navigateur colle avec
-- Ctrl+V, lire le presse-papiers en OSC 52 bloquerait sous tmux)
local osc52 = require("vim.ui.clipboard.osc52")
local function paste()
  return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
end
vim.g.clipboard = {
  name = "OSC 52",
  copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
  paste = { ["+"] = paste, ["*"] = paste },
}
