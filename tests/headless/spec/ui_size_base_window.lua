local M = {}

function M.run()
  vim.cmd("only")
  vim.cmd("enew")
  vim.cmd("vsplit")

  local source_win = vim.api.nvim_get_current_win()
  local source_width = vim.api.nvim_win_get_width(source_win)

  local ui = require("translate.ui")
  local config = require("translate.config").build({
    float = {
      min_width = 1,
      min_height = 1,
      inherit_view = false,
      center_vertical = false,
    },
  })

  ui.show_result("hello", config, { model = "DeepL" })

  local float_win = vim.api.nvim_get_current_win()
  local float_config = vim.api.nvim_win_get_config(float_win)
  local actual_width = float_config.width

  pcall(vim.api.nvim_win_close, float_win, true)
  vim.cmd("only")

  assert(
    actual_width == source_width,
    ("float width should match source window width by default (expected %d, got %d)"):format(
      source_width,
      actual_width or -1
    )
  )
end

return M
