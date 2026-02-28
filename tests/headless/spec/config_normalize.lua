local M = {}

function M.run()
  local config = require("translate.config")
  local cfg = config.build({
    engine = " google ",
    default_target = " en-us ",
    target_lang = " ko ",
    api_key = "  deepl-key  ",
    google_api_key = "  google-key  ",
  })

  assert(cfg.engine == "google", "engine trim/lower normalize failed")
  assert(cfg.default_target == "EN-US", "default_target trim/upper normalize failed")
  assert(cfg.target_lang == "KO", "target_lang trim/upper normalize failed")
  assert(cfg.api_key == "deepl-key", "api_key trim normalize failed")
  assert(cfg.google_api_key == "google-key", "google_api_key trim normalize failed")

  local invalid_key_cfg = config.build({
    engine_labels = {
      [1] = "Oops",
    },
  })
  assert(invalid_key_cfg.engine_labels.deepl == "DeepL", "non-string engine label key must be ignored")

  local blank_label_cfg = config.build({
    engine_labels = {
      google = "",
    },
  })
  assert(blank_label_cfg.engine_labels.google == "Google", "blank engine label must not override defaults")

  local invalid_secret_cfg = config.build({
    api_key = "deep\nl-key",
    google_api_key = "google\r\nkey",
  })
  assert(invalid_secret_cfg.api_key == nil, "api_key containing newlines must be rejected")
  assert(invalid_secret_cfg.google_api_key == nil, "google_api_key containing newlines must be rejected")

  local bool_cfg = config.build({
    free_api = 0,
    persist_target = "false",
    float = {
      inherit_view = "0",
      center_vertical = 1,
    },
  })
  assert(bool_cfg.free_api == false, "numeric 0 must disable free_api")
  assert(bool_cfg.persist_target == false, "string false must disable persist_target")
  assert(bool_cfg.float.inherit_view == false, "string 0 must disable inherit_view")
  assert(bool_cfg.float.center_vertical == true, "numeric 1 must enable center_vertical")

  -- Float ratio clamping tests
  local ratio_high_cfg = config.build({
    float = { width_ratio = 1.5, height_ratio = 2.0 },
  })
  assert(ratio_high_cfg.float.width_ratio == 1.0, "width_ratio > 1.0 must be clamped to 1.0")
  assert(ratio_high_cfg.float.height_ratio == 1.0, "height_ratio > 1.0 must be clamped to 1.0")

  local ratio_low_cfg = config.build({
    float = { width_ratio = -0.5, height_ratio = -1.0 },
  })
  assert(ratio_low_cfg.float.width_ratio == 0, "width_ratio < 0.0 must be clamped to 0")
  assert(ratio_low_cfg.float.height_ratio == 0, "height_ratio < 0.0 must be clamped to 0")

  local ratio_nil_cfg = config.build({
    float = { width_ratio = nil, height_ratio = nil },
  })
  assert(ratio_nil_cfg.float.width_ratio == 1.0, "nil width_ratio must use default 1.0")
  assert(ratio_nil_cfg.float.height_ratio == 1.0, "nil height_ratio must use default 1.0")

  local ratio_string_cfg = config.build({
    float = { width_ratio = "0.5", height_ratio = "bad" },
  })
  assert(ratio_string_cfg.float.width_ratio == 1.0, "non-number width_ratio must use default")
  assert(ratio_string_cfg.float.height_ratio == 1.0, "non-number height_ratio must use default")

  -- Float min dimension validation tests
  local min_negative_cfg = config.build({
    float = { min_width = -10, min_height = -5 },
  })
  assert(min_negative_cfg.float.min_width == 40, "negative min_width must use default 40")
  assert(min_negative_cfg.float.min_height == 8, "negative min_height must use default 8")

  local min_zero_cfg = config.build({
    float = { min_width = 0, min_height = 0 },
  })
  assert(min_zero_cfg.float.min_width == 40, "zero min_width must use default 40")
  assert(min_zero_cfg.float.min_height == 8, "zero min_height must use default 8")

  local min_string_cfg = config.build({
    float = { min_width = "wide", min_height = "tall" },
  })
  assert(min_string_cfg.float.min_width == 40, "string min_width must use default 40")
  assert(min_string_cfg.float.min_height == 8, "string min_height must use default 8")

  local min_nil_cfg = config.build({
    float = { min_width = nil, min_height = nil },
  })
  assert(min_nil_cfg.float.min_width == 40, "nil min_width must use default 40")
  assert(min_nil_cfg.float.min_height == 8, "nil min_height must use default 8")

  local min_float_cfg = config.build({
    float = { min_width = 40.5, min_height = 8.7 },
  })
  assert(min_float_cfg.float.min_width == 40, "non-integer min_width must use default 40")
  assert(min_float_cfg.float.min_height == 8, "non-integer min_height must use default 8")

  local min_valid_cfg = config.build({
    float = { min_width = 60, min_height = 10 },
  })
  assert(min_valid_cfg.float.min_width == 60, "valid min_width must be preserved")
  assert(min_valid_cfg.float.min_height == 10, "valid min_height must be preserved")

  -- Deprecated max_width_ratio / max_height_ratio are no longer migrated;
  -- only the modern width_ratio / height_ratio names are recognized.
end

return M
