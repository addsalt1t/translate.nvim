local M = {}

local BLOCKWISE_VISUAL_MODE = "\22"

local function normalize_selection(srow, scol, erow, ecol)
  if srow > erow or (srow == erow and scol > ecol) then
    return erow, ecol, srow, scol
  end

  return srow, scol, erow, ecol
end

local function is_visual_mode(mode)
  return mode == "v" or mode == "V" or mode == BLOCKWISE_VISUAL_MODE
end

local function line_end_col(row)
  local line = vim.api.nvim_buf_get_lines(0, row, row + 1, true)[1] or ""
  return #line
end

local function build_visual_bounds(mode, srow, scol, erow, ecol)
  srow, scol, erow, ecol = normalize_selection(srow, scol, erow, ecol)

  local end_col = ecol + 1
  if mode == "V" then
    scol = 0
    end_col = line_end_col(erow)
  end

  return {
    mode = mode,
    srow = srow,
    scol = scol,
    erow = erow,
    end_col = end_col,
  }
end

local function has_valid_mark(mark)
  return type(mark) == "table" and #mark >= 2 and type(mark[1]) == "number" and mark[1] > 0 and type(mark[2]) == "number"
end

local function get_visual_bounds_from_mode(mode)
  local visual_start = vim.fn.getpos("v")
  local cursor = vim.fn.getpos(".")
  if type(visual_start) ~= "table" or type(cursor) ~= "table" then
    return nil
  end

  local srow, scol = visual_start[2] - 1, visual_start[3] - 1
  local erow, ecol = cursor[2] - 1, cursor[3] - 1
  return build_visual_bounds(mode, srow, scol, erow, ecol)
end

local function get_visual_bounds_from_marks()
  local visual_mode = vim.fn.visualmode()
  local start_mark = vim.api.nvim_buf_get_mark(0, "<")
  local end_mark = vim.api.nvim_buf_get_mark(0, ">")
  if not has_valid_mark(start_mark) or not has_valid_mark(end_mark) then
    return nil
  end

  local srow, scol = start_mark[1] - 1, start_mark[2]
  local erow, ecol = end_mark[1] - 1, end_mark[2]
  return build_visual_bounds(visual_mode, srow, scol, erow, ecol)
end

function M.get_visual_text()
  local mode = vim.fn.mode()
  local bounds = nil

  if is_visual_mode(mode) then
    bounds = get_visual_bounds_from_mode(mode)
  else
    bounds = get_visual_bounds_from_marks()
  end

  if not bounds then
    return nil, "No visual selection found. Please select text in visual mode and try again."
  end
  if bounds.mode == BLOCKWISE_VISUAL_MODE then
    return nil, "Blockwise visual mode is not supported. Use charwise (v) or linewise (V)."
  end

  local lines = vim.api.nvim_buf_get_text(0, bounds.srow, bounds.scol, bounds.erow, bounds.end_col, {})
  local text = table.concat(lines, "\n")
  if text == "" then
    return nil, "No text selected. Select text in visual mode and try again."
  end

  return text
end

return M
