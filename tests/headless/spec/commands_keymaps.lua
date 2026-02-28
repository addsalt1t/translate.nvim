local M = {}

function M.run()
  vim.g.loaded_translate_nvim = nil
  dofile("plugin/translate.lua")

  assert(vim.fn.exists(":TranslateSelectTarget") == 2, "TranslateSelectTarget command is missing")
  assert(vim.fn.exists(":TranslateSelectEngine") == 2, "TranslateSelectEngine command is missing")

  local translate = require("translate")
  translate.setup({
    engine = "deepl",
    api_key = "dummy",
    persist_target = false,
    keymaps = {
      translate_visual = "<Space>tr",
      select_target = "<Space>tl",
      select_engine = "<Space>te",
    },
  })

  local map = vim.fn.maparg("<Space>te", "n")
  assert(type(map) == "string" and map ~= "", "engine keymap (<Space>te) is missing")
end

return M
