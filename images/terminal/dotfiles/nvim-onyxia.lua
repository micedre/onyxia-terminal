
-- Ajouts de l'image au options.lua de LazyVim.

-- Presse-papiers : la copie part en OSC 52 vers tmux puis le
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

-- Thème clair / sombre du terminal web : @theme de tmux (choisi dans la page,
-- Alt+m), sinon celui d'Onyxia. Appliqué après le chargement du thème de
-- couleurs (tokyonight passe alors en style « day » / « moon ») ; les Neovim
-- ouverts sont mis à jour par /opt/onyxia-terminal/theme.sh sync
local function onyxia_background()
  if vim.env.TMUX then
    local t = vim.trim(vim.fn.system({ "tmux", "show", "-gqv", "@theme" }))
    if t == "light" or t == "dark" then return t end
  end
  return vim.env.DARK_MODE == "true" and "dark" or "light"
end
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    local bg = onyxia_background()
    if vim.o.background ~= bg then vim.o.background = bg end
  end,
})
