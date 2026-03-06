local M = {}

function M.run()
  vim.g.loaded_translate_nvim = nil
  dofile("plugin/translate.lua")

  assert(vim.fn.exists(":TranslateSelectTarget") == 2, "TranslateSelectTarget command is missing")
  assert(vim.fn.exists(":TranslateFile") == 2, "TranslateFile command is missing")
  assert(vim.fn.exists(":TranslateSelectEngine") == 2, "TranslateSelectEngine command is missing")

  local translate = require("translate")
  translate.setup({
    engine = "deepl",
    api_key = "dummy",
    persist_target = false,
  })

  local file_map = vim.fn.maparg("<Space>tf", "n")
  assert(file_map == "", "translate_file keymap should be disabled by default")

  translate.setup({
    engine = "deepl",
    api_key = "dummy",
    persist_target = false,
    keymaps = {
      translate_visual = "<Space>tr",
      translate_file = "<Space>tf",
      select_target = "<Space>tl",
      select_engine = "<Space>te",
    },
  })

  local map = vim.fn.maparg("<Space>te", "n")
  assert(type(map) == "string" and map ~= "", "engine keymap (<Space>te) is missing")
  local translate_file_map = vim.fn.maparg("<Space>tf", "n")
  assert(type(translate_file_map) == "string" and translate_file_map ~= "", "translate_file keymap (<Space>tf) should be opt-in")

  local notifications = {}
  local original_notify = vim.notify
  vim.notify = function(message, level, opts)
    table.insert(notifications, {
      message = message,
      level = level,
      opts = opts,
    })
  end

  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  translate.translate_file()
  local warned = vim.wait(500, function()
    return #notifications > 0
  end, 20)
  assert(warned, "translate_file should warn for an empty buffer")
  assert(string.find(notifications[1].message or "", "Buffer is empty", 1, true), "translate_file empty-buffer warning mismatch")

  local deepl = require("translate.deepl")
  local ui = require("translate.ui")
  local original_translate = deepl.translate
  local original_show_result = ui.show_result
  local captured_text
  deepl.translate = function(_, text, on_done)
    captured_text = text
    on_done(nil, "translated file")
  end
  ui.show_result = function() end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "alpha", "beta" })
  translate.translate_file()
  local dispatched = vim.wait(500, function()
    return captured_text ~= nil
  end, 20)

  deepl.translate = original_translate
  ui.show_result = original_show_result
  vim.notify = original_notify

  assert(dispatched, "translate_file should dispatch non-empty buffer text to the provider")
  assert(captured_text == "alpha\nbeta", ("translate_file dispatched unexpected text: %s"):format(tostring(captured_text)))
end

return M
