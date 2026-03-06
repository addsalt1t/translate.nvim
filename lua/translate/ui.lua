local M = {}

--- Edge margin subtracted from editor dimensions when clamping window size.
local EDGE_MARGIN = 4

local current = {
  win = nil,
  buf = nil,
}

local win_view_options = {
  "showbreak",
  "list",
  "listchars",
  "sidescroll",
  "sidescrolloff",
}

local buf_view_options = {
  "tabstop",
  "vartabstop",
  "softtabstop",
  "shiftwidth",
  "expandtab",
}

--- Close and clean up the current floating window and buffer.
local function close_current()
  if current.win and vim.api.nvim_win_is_valid(current.win) then
    pcall(vim.api.nvim_win_close, current.win, true)
  end
  if current.buf and vim.api.nvim_buf_is_valid(current.buf) then
    pcall(vim.api.nvim_buf_delete, current.buf, { force = true })
  end
  current.win = nil
  current.buf = nil
end

local function copy_local_options(source, target, options, scope)
  for _, option in ipairs(options) do
    pcall(function()
      scope[target][option] = scope[source][option]
    end)
  end
end

--- Open a floating window, falling back to a title-less config on error.
---@param buf number Buffer handle
---@param config table nvim_open_win config
---@return number win Window handle
local function open_result_window(buf, config)
  local ok, win_or_err = pcall(vim.api.nvim_open_win, buf, true, config)
  if ok then
    return win_or_err
  end

  local fallback = vim.deepcopy(config)
  fallback.title = nil
  fallback.title_pos = nil
  return vim.api.nvim_open_win(buf, true, fallback)
end

--- Calculate floating window geometry (size and position).
---@param float_opts table Float window configuration from user config
---@param source_win number Source window handle
---@return table geometry { width, height, row, col }
local function calculate_geometry(float_opts, source_win)
  local size_base = type(float_opts.size_base) == "string" and float_opts.size_base:lower() or "window"
  if size_base ~= "window" and size_base ~= "editor" then
    size_base = "window"
  end

  local width_ratio = float_opts.width_ratio or 1.0
  local height_ratio = float_opts.height_ratio or 1.0
  local width_offset = tonumber(float_opts.width_offset) or 0
  local height_offset = tonumber(float_opts.height_offset) or 0
  local min_width = float_opts.min_width or 40
  local min_height = float_opts.min_height or 8
  local absolute_width = float_opts.width
  local absolute_height = float_opts.height

  local base_width
  local base_height
  local base_row = 0
  local base_col = 0

  if size_base == "window" and vim.api.nvim_win_is_valid(source_win) then
    base_width = vim.api.nvim_win_get_width(source_win)
    base_height = vim.api.nvim_win_get_height(source_win)
    local pos = vim.api.nvim_win_get_position(source_win)
    base_row = pos[1] or 0
    base_col = pos[2] or 0
  else
    base_width = vim.o.columns
    base_height = vim.o.lines
    size_base = "editor"
  end

  local width = absolute_width or (math.floor(base_width * width_ratio) + width_offset)
  local height = absolute_height or (math.floor(base_height * height_ratio) + height_offset)

  local max_width = math.max(1, vim.o.columns - EDGE_MARGIN)
  local max_height = math.max(1, vim.o.lines - EDGE_MARGIN)
  if size_base == "window" then
    max_width = math.max(1, math.min(max_width, base_width))
    max_height = math.max(1, math.min(max_height, base_height))
  end

  local effective_min_width = math.min(min_width, max_width)
  local effective_min_height = math.min(min_height, max_height)
  width = math.max(effective_min_width, math.min(math.max(width, 1), max_width))
  height = math.max(effective_min_height, math.min(math.max(height, 1), max_height))

  local row
  local col
  if size_base == "window" then
    row = base_row + math.floor((base_height - height) / 2)
    col = base_col + math.floor((base_width - width) / 2)
  else
    row = math.floor((vim.o.lines - height) / 2 - 1)
    col = math.floor((vim.o.columns - width) / 2)
  end
  row = math.max(0, row)
  col = math.max(0, col)

  return { width = width, height = height, row = row, col = col }
end

--- Pad lines with empty strings so content appears vertically centered.
---@param lines string[] Content lines
---@param height number Window height
---@return string[] padded_lines Lines with vertical padding
local function center_lines_vertically(lines, height)
  if #lines >= height then
    return lines
  end

  local padding = height - #lines
  local top_padding = math.floor(padding / 2)
  local bottom_padding = padding - top_padding
  local padded = {}

  for _ = 1, top_padding do
    table.insert(padded, "")
  end
  vim.list_extend(padded, lines)
  for _ = 1, bottom_padding do
    table.insert(padded, "")
  end

  return padded
end

local function build_rendered_lines(text, height, center_vertical)
  local lines = vim.split(text, "\n", { plain = true, trimempty = false })
  if #lines == 0 then
    lines = { "" }
  end

  if center_vertical then
    return center_lines_vertically(lines, height)
  end

  return lines
end

local function apply_result_window_options(win, float)
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].breakindent = true
  vim.wo[win].breakindentopt = "shift:2"
  vim.wo[win].cursorline = false
  vim.wo[win].winfixwidth = true
  vim.wo[win].winfixheight = true

  if type(float.winhighlight) == "string" and float.winhighlight ~= "" then
    vim.wo[win].winhighlight = float.winhighlight
  end
end

local function set_close_keymaps(buf)
  vim.keymap.set("n", "q", close_current, { buffer = buf, silent = true, nowait = true })
  vim.keymap.set("n", "<Esc>", close_current, { buffer = buf, silent = true, nowait = true })
end

--- Display a translation result in a floating window.
---@param text string Translated text content
---@param config table Plugin configuration table (must contain `float` key)
---@param meta table|nil Optional metadata (e.g. { model = "DeepL" })
function M.show_result(text, config, meta)
  close_current()

  local source_win = vim.api.nvim_get_current_win()
  local source_buf = vim.api.nvim_win_get_buf(source_win)

  local float = config.float or {}
  local inherit_view = float.inherit_view
  local center_vertical = float.center_vertical
  local model = meta and meta.model

  local geom = calculate_geometry(float, source_win)
  local rendered_lines = build_rendered_lines(text, geom.height, center_vertical)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "translate-result"

  if inherit_view and vim.api.nvim_win_is_valid(source_win) and vim.api.nvim_buf_is_valid(source_buf) then
    copy_local_options(source_buf, buf, buf_view_options, vim.bo)
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, rendered_lines)
  vim.bo[buf].modifiable = false

  local win = open_result_window(buf, {
    relative = "editor",
    style = "minimal",
    border = float.border,
    title = type(model) == "string" and model ~= "" and (" " .. model .. " ") or nil,
    title_pos = "center",
    width = geom.width,
    height = geom.height,
    row = geom.row,
    col = geom.col,
  })

  if inherit_view and vim.api.nvim_win_is_valid(source_win) then
    copy_local_options(source_win, win, win_view_options, vim.wo)
  end
  apply_result_window_options(win, float)
  set_close_keymaps(buf)

  current.win = win
  current.buf = buf
end

return M
