local M = {}
local FALSEY_STRINGS = {
  ["0"] = true,
  ["false"] = true,
  ["off"] = true,
  ["no"] = true,
}
local TRUTHY_STRINGS = {
  ["1"] = true,
  ["true"] = true,
  ["on"] = true,
  ["yes"] = true,
}

---@param value any Value to trim
---@return string|nil
function M.trim_to_nil(value)
  if type(value) ~= "string" then
    return nil
  end

  local trimmed = vim.trim(value)
  if trimmed == "" then
    return nil
  end

  return trimmed
end

---@param value any Value to normalize as uppercase code
---@return string|nil
function M.upper_code(value)
  local trimmed = M.trim_to_nil(value)
  if not trimmed then
    return nil
  end
  return trimmed:upper()
end

---@param value any Value to normalize as lowercase name
---@return string|nil
function M.lower_name(value)
  local trimmed = M.trim_to_nil(value)
  if not trimmed then
    return nil
  end
  return trimmed:lower()
end

---@param value any Value to validate as single-line secret
---@return string|nil
function M.single_line_secret(value)
  local trimmed = M.trim_to_nil(value)
  if not trimmed then
    return nil
  end

  if string.find(trimmed, "[\r\n]") then
    return nil
  end

  return trimmed
end

---@param value any Value to check for non-empty text
---@return boolean
function M.has_text(value)
  return M.trim_to_nil(value) ~= nil
end

---@param value any Value to coerce to boolean
---@param default_value boolean Default if value cannot be coerced
---@return boolean
function M.boolean(value, default_value)
  if value == nil then
    return default_value
  end

  if type(value) == "boolean" then
    return value
  end

  if type(value) == "number" then
    return value ~= 0
  end

  local trimmed = M.trim_to_nil(value)
  if not trimmed then
    return default_value
  end

  local normalized = trimmed:lower()
  if FALSEY_STRINGS[normalized] then
    return false
  end
  if TRUTHY_STRINGS[normalized] then
    return true
  end

  return default_value
end

---@param value any Value to clamp
---@param min number Minimum allowed value
---@param max number Maximum allowed value
---@param default number Default if value is not a number
---@return number
function M.clamp_number(value, min, max, default)
  if type(value) ~= "number" then
    return default
  end
  return math.max(min, math.min(max, value))
end

---@param value any Value to validate
---@param default integer Default if value is not a positive integer
---@return integer
function M.positive_integer(value, default)
  if type(value) ~= "number" or value < 1 or math.floor(value) ~= value then
    return default
  end
  return value
end

return M
