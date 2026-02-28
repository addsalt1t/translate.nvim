local M = {}

function M.run()
  local ui = require("translate.ui")
  local config = {
    float = {
      border = "rounded",
      winhighlight = "NormalFloat:Normal",
      width = 40,
      height = 8,
      min_width = 20,
      min_height = 4,
      inherit_view = false,
      center_vertical = false,
    },
  }

  ui.show_result("hello", config, { model = "Google" })

  local win = vim.api.nvim_get_current_win()
  local conf = vim.api.nvim_win_get_config(win)
  assert(conf.title ~= nil, "float title should be set")
  assert(vim.wo[win].winhighlight == "NormalFloat:Normal", "winhighlight should match default override")
end

return M
