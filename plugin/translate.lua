if vim.g.loaded_translate_nvim == 1 then
  return
end
vim.g.loaded_translate_nvim = 1

require("translate").setup()

vim.api.nvim_create_user_command("TranslateSelectTarget", function()
  require("translate").select_target()
end, {
  desc = "Select target language for current translate.nvim engine",
})

vim.api.nvim_create_user_command("TranslateSelectEngine", function()
  require("translate").select_engine()
end, {
  desc = "Select translation engine for translate.nvim",
})
