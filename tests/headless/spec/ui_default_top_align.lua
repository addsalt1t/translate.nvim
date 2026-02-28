local M = {}

local function render_lines(float_opts)
  vim.cmd("enew")

  local ui = require("translate.ui")
  local config = require("translate.config").build({
    float = vim.tbl_extend("force", {
      width = 40,
      height = 7,
      min_width = 20,
      min_height = 4,
      inherit_view = false,
    }, float_opts or {}),
  })

  ui.show_result("hello", config, { model = "DeepL" })

  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  pcall(vim.api.nvim_win_close, win, true)

  return lines
end

function M.run()
  local top_aligned = render_lines()
  assert(top_aligned[1] == "hello", "default result text should start at top without extra blank padding")

  local centered_numeric = render_lines({
    center_vertical = 1,
  })
  assert(centered_numeric[1] == "", "numeric center_vertical=1 should add top padding")
  assert(centered_numeric[4] == "hello", "numeric center_vertical=1 should vertically center short text")
end

return M
