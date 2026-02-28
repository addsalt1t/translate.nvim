local M = {}

function M.run()
  vim.cmd("enew")
  local source_win = vim.api.nvim_get_current_win()
  vim.wo[source_win].wrap = false
  vim.wo[source_win].linebreak = false

  local ui = require("translate.ui")
  local config = require("translate.config").build({
    float = {
      width = 40,
      height = 8,
      min_width = 20,
      min_height = 4,
      inherit_view = true,
      center_vertical = false,
    },
  })

  ui.show_result(string.rep("W", 200), config, { model = "DeepL" })

  local result_win = vim.api.nvim_get_current_win()
  assert(vim.wo[result_win].wrap == true, "result window wrap must always be enabled")
  assert(vim.wo[result_win].linebreak == true, "result window linebreak must always be enabled")
end

return M
