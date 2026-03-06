local M = {}

local function close_if_valid(win)
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
end

local function press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end

local function reset_to_regular_window()
  local current_config = vim.api.nvim_win_get_config(0)
  if type(current_config.relative) == "string" and current_config.relative ~= "" then
    pcall(vim.api.nvim_win_close, 0, true)
  end
  vim.cmd("silent! only")
end

function M.run()
  local ui = require("translate.ui")
  local config_module = require("translate.config")

  reset_to_regular_window()
  vim.cmd("enew")
  vim.cmd("vsplit")

  local source_win = vim.api.nvim_get_current_win()
  local source_buf = vim.api.nvim_win_get_buf(source_win)
  vim.wo[source_win].showbreak = "> "
  vim.wo[source_win].list = true
  vim.wo[source_win].listchars = "tab:>-,trail:."
  vim.bo[source_buf].tabstop = 3
  vim.bo[source_buf].shiftwidth = 5

  local config = config_module.build({
    float = {
      size_base = "editor",
      width_ratio = 0.5,
      height_ratio = 0.5,
      width_offset = 3,
      height_offset = 2,
      min_width = 1,
      min_height = 1,
      inherit_view = true,
      center_vertical = false,
    },
  })

  ui.show_result("first result", config, { model = "DeepL" })

  local first_win = vim.api.nvim_get_current_win()
  local first_buf = vim.api.nvim_win_get_buf(first_win)
  local first_conf = vim.api.nvim_win_get_config(first_win)
  local expected_width = math.floor(vim.o.columns * 0.5) + 3
  local expected_height = math.floor(vim.o.lines * 0.5) + 2

  assert(first_conf.width == expected_width, ("editor-based float width mismatch: %d"):format(first_conf.width or -1))
  assert(first_conf.height == expected_height, ("editor-based float height mismatch: %d"):format(first_conf.height or -1))
  assert(vim.wo[first_win].showbreak == vim.wo[source_win].showbreak, "result window should inherit showbreak")
  assert(vim.wo[first_win].list == vim.wo[source_win].list, "result window should inherit list")
  assert(vim.wo[first_win].listchars == vim.wo[source_win].listchars, "result window should inherit listchars")
  assert(vim.bo[first_buf].tabstop == vim.bo[source_buf].tabstop, "result buffer should inherit tabstop")
  assert(vim.bo[first_buf].shiftwidth == vim.bo[source_buf].shiftwidth, "result buffer should inherit shiftwidth")

  ui.show_result("second result", config, { model = "DeepL" })

  local second_win = vim.api.nvim_get_current_win()
  local second_buf = vim.api.nvim_win_get_buf(second_win)
  local second_lines = vim.api.nvim_buf_get_lines(second_buf, 0, -1, false)

  assert(not vim.api.nvim_win_is_valid(first_win), "show_result should replace the previous floating window")
  assert(not vim.api.nvim_buf_is_valid(first_buf), "show_result should wipe the previous floating buffer")
  assert(second_lines[1] == "second result", "replacement float should render the latest text")

  press("q")
  local q_closed = vim.wait(1000, function()
    return not vim.api.nvim_win_is_valid(second_win)
  end, 20)
  assert(q_closed, "q should close the result float")

  ui.show_result("third result", config, { model = "DeepL" })
  local third_win = vim.api.nvim_get_current_win()

  press("<Esc>")
  local esc_closed = vim.wait(1000, function()
    return not vim.api.nvim_win_is_valid(third_win)
  end, 20)
  assert(esc_closed, "<Esc> should close the result float")

  close_if_valid(first_win)
  close_if_valid(second_win)
  close_if_valid(third_win)
  reset_to_regular_window()
end

return M
