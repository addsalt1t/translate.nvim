local M = {}
local normalize = require("translate.normalize")

local function read_file(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  local lines = vim.fn.readfile(path)
  if not lines or #lines == 0 then
    return nil
  end
  return table.concat(lines, "\n")
end

local function validate_path(path)
  if not normalize.has_text(path) then
    return false, "state_path is invalid. Use an absolute path like /tmp/translate.nvim/state.json."
  end
  if vim.fn.isabsolutepath(path) ~= 1 then
    return false, ("state_path must be an absolute path, got: %s"):format(path)
  end
  return true
end

---Load persisted state from a JSON file.
---@param path string absolute path to the state file
---@return table|nil state table with `target_lang` and `engine`, or nil on failure
function M.load(path)
  local raw = read_file(path)
  if not raw then
    return nil
  end

  local ok, data = pcall(vim.json.decode, raw)
  if not ok or type(data) ~= "table" then
    vim.notify("translate.nvim: failed to decode state file: " .. path, vim.log.levels.WARN)
    return nil
  end

  local target_lang = normalize.upper_code(data.target_lang)
  local engine = normalize.lower_name(data.engine)
  if not target_lang and not engine then
    return nil
  end

  return {
    target_lang = target_lang,
    engine = engine,
  }
end

---Persist state to a JSON file.
---@param path string absolute path to the state file
---@param state table with optional `target_lang` and `engine` fields
---@return boolean success
---@return string|nil error message on failure
function M.save(path, state)
  local valid, validation_err = validate_path(path)
  if not valid then
    return false, validation_err
  end

  local normalized = {
    target_lang = normalize.upper_code(state.target_lang),
    engine = normalize.lower_name(state.engine),
  }

  if not normalized.target_lang and not normalized.engine then
    return false, "Failed to persist state: both target_lang and engine are empty."
  end

  local dir = vim.fs.dirname(path)
  if vim.fn.isdirectory(dir) ~= 1 and vim.fn.mkdir(dir, "p") == 0 then
    return false, ("Failed to create state directory: %s"):format(dir)
  end

  local payload = vim.json.encode(normalized)
  local write_ok, err = pcall(vim.fn.writefile, { payload }, path)
  if not write_ok then
    return false, ("Failed to persist state to %s: %s"):format(path, err)
  end

  return true
end

---Validate a state file path.
---@param path string path to validate
---@return boolean valid
---@return string|nil error message if invalid
function M.validate_path(path)
  return validate_path(path)
end

return M
