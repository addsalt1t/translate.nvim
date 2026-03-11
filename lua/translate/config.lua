local M = {}
local normalize = require("translate.normalize")

local defaults = {
  api_key = vim.env.DEEPL_AUTH_KEY,
  google_api_key = vim.env.GOOGLE_TRANSLATE_API_KEY or vim.env.GOOGLE_API_KEY,
  engine = "deepl",
  engine_labels = {
    deepl = "DeepL",
    google = "Google",
  },
  free_api = true,
  default_target = "KO",
  target_lang = nil,
  persist_target = true,
  state_path = vim.fs.normalize(vim.fn.stdpath("state") .. "/translate.nvim/state.json"),
  keymaps = {
    translate_visual = "<Space>tr",
    translate_file = "<Space>tf",
    select_target = "<Space>tl",
    select_engine = "<Space>te",
  },
  float = {
    border = "rounded",
    -- Match floating text area to Normal highlight by default.
    winhighlight = "NormalFloat:Normal,FloatBorder:Normal",
    -- Base float size on current source window by default.
    size_base = "window",
    width_ratio = 1.0,
    height_ratio = 1.0,
    -- Optional additive adjustments after ratio calculation.
    width_offset = 0,
    height_offset = 0,
    min_width = 40,
    min_height = 8,
    inherit_view = true,
    center_vertical = false,
  },
}

local function normalize_engine(engine)
  return normalize.lower_name(engine) or "deepl"
end

local function validate_keymaps(opts)
  if opts.keymaps ~= nil and type(opts.keymaps) ~= "table" then
    error("translate.nvim setup error: keymaps must be a table; set entries to '' to disable.")
  end
end

local function validate_float_absolute_dimension(value, option_name)
  if value == nil then
    return
  end
  if type(value) ~= "number" or value < 1 or math.floor(value) ~= value then
    error(("translate.nvim setup error: %s must be a positive integer."):format(option_name))
  end
end

local function normalize_engine_labels(labels)
  local normalized = {}
  if type(labels) ~= "table" then
    return normalized
  end

  for engine, label in pairs(labels) do
    local normalized_engine = normalize.lower_name(normalize.single_line_secret(engine))
    local normalized_label = normalize.single_line_secret(label)
    if normalized_engine and normalized_label then
      normalized[normalized_engine] = normalized_label
    end
  end

  return normalized
end

---Build a fully normalized config from user options merged over defaults.
---@param user_opts table|nil
---@return table
function M.build(user_opts)
  local opts = vim.tbl_deep_extend("force", {}, defaults, user_opts or {})
  validate_keymaps(opts)
  opts.api_key = normalize.single_line_secret(opts.api_key)
  opts.google_api_key = normalize.single_line_secret(opts.google_api_key)
  opts.engine = normalize_engine(opts.engine)
  opts.engine_labels = vim.tbl_extend(
    "force",
    normalize_engine_labels(defaults.engine_labels),
    normalize_engine_labels(opts.engine_labels)
  )
  opts.default_target = normalize.upper_code(opts.default_target) or "KO"
  opts.target_lang = normalize.upper_code(opts.target_lang) or opts.default_target
  opts.free_api = normalize.boolean(opts.free_api, true)
  opts.persist_target = normalize.boolean(opts.persist_target, true)

  if type(opts.float) ~= "table" then
    opts.float = vim.deepcopy(defaults.float)
  end
  opts.float.inherit_view = normalize.boolean(opts.float.inherit_view, true)
  opts.float.center_vertical = normalize.boolean(opts.float.center_vertical, false)

  -- Clamp ratio values to 0.0-1.0 range.
  opts.float.width_ratio = normalize.clamp_number(opts.float.width_ratio, 0, 1, defaults.float.width_ratio)
  opts.float.height_ratio = normalize.clamp_number(opts.float.height_ratio, 0, 1, defaults.float.height_ratio)

  -- Validate min dimensions as positive integers.
  opts.float.min_width = normalize.positive_integer(opts.float.min_width, defaults.float.min_width)
  opts.float.min_height = normalize.positive_integer(opts.float.min_height, defaults.float.min_height)
  validate_float_absolute_dimension(opts.float.width, "float.width")
  validate_float_absolute_dimension(opts.float.height, "float.height")

  return opts
end

return M
