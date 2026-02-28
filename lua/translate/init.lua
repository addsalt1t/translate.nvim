local config_module = require("translate.config")
local normalize = require("translate.normalize")
local state = require("translate.state")
local ui = require("translate.ui")

local providers = {
  deepl = require("translate.deepl"),
  google = require("translate.google"),
}

local M = {
  _config = nil,
  _target_cache = {},
  _keymaps = {},
  _next_request_id = 0,
  _active_request_id = nil,
}

local function notify(message, level)
  vim.schedule(function()
    vim.notify(message, level or vim.log.levels.INFO, { title = "translate.nvim" })
  end)
end

local function clear_keymaps()
  for _, map in ipairs(M._keymaps) do
    pcall(vim.keymap.del, map.mode, map.lhs)
  end
  M._keymaps = {}
end

local function set_keymap(modes, lhs, rhs, desc)
  if type(lhs) ~= "string" or lhs == "" then
    return
  end

  local mode_list = type(modes) == "table" and modes or { modes }
  for _, mode in ipairs(mode_list) do
    vim.keymap.set(mode, lhs, rhs, { silent = true, desc = desc })
    table.insert(M._keymaps, { mode = mode, lhs = lhs })
  end
end

local function ensure_setup()
  if not M._config then
    M.setup()
  end
  return M._config
end

local function available_engines()
  local engines = vim.tbl_keys(providers)
  table.sort(engines)
  return engines
end

local function resolve_provider_by_engine(engine)
  local provider = providers[engine]
  if provider then
    return provider
  end
  return nil, ("Unsupported engine '%s'. Available engines: %s"):format(engine, table.concat(available_engines(), ", "))
end

local function resolve_provider_label(cfg, engine)
  engine = engine or cfg.engine
  local label = cfg.engine_labels[engine]
  if type(label) == "string" and label ~= "" then
    return label
  end
  return engine:upper()
end

local function has_explicit_engine_option(opts)
  return type(opts) == "table" and opts.engine ~= nil
end

local function normalize_target_for_provider(provider, target)
  local normalized = normalize.upper_code(target)
  if not normalized then
    return nil
  end

  if type(provider.normalize_target) == "function" then
    normalized = provider.normalize_target(normalized)
  end

  return normalized
end

local function is_target_supported_for_provider(provider, target)
  if not target then
    return false
  end

  if type(provider.is_target_supported) == "function" then
    return provider.is_target_supported(target)
  end

  return true
end

local function normalize_with_fallback_target(cfg, provider, candidate)
  local normalized = normalize_target_for_provider(provider, candidate)
  if normalized and is_target_supported_for_provider(provider, normalized) then
    return normalized
  end

  local fallback = normalize_target_for_provider(provider, cfg.default_target)
  if fallback and is_target_supported_for_provider(provider, fallback) then
    return fallback
  end

  return nil
end

local function invalidate_active_translation()
  M._active_request_id = nil
end

local function begin_translation_request()
  M._next_request_id = M._next_request_id + 1
  M._active_request_id = M._next_request_id
  return M._next_request_id
end

local function is_active_translation_request(request_id)
  return request_id == M._active_request_id
end

local function build_translation_snapshot(cfg)
  return {
    api_key = cfg.api_key,
    google_api_key = cfg.google_api_key,
    free_api = cfg.free_api,
    target_lang = cfg.target_lang,
  }
end

local function normalize_selection(srow, scol, erow, ecol)
  if srow > erow or (srow == erow and scol > ecol) then
    return erow, ecol, srow, scol
  end
  return srow, scol, erow, ecol
end

local function is_visual_mode(mode)
  return mode == "v" or mode == "V" or mode == "\22"
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
  if vim.tbl_isempty(start_mark) or vim.tbl_isempty(end_mark) then
    return nil
  end

  local srow, scol = start_mark[1] - 1, start_mark[2]
  local erow, ecol = end_mark[1] - 1, end_mark[2]
  return build_visual_bounds(visual_mode, srow, scol, erow, ecol)
end

local function get_visual_text()
  local mode = vim.fn.mode()
  local bounds = is_visual_mode(mode) and get_visual_bounds_from_mode(mode) or get_visual_bounds_from_marks()
  if not bounds then
    return nil, "No visual selection found. Please select text in visual mode and try again."
  end
  if bounds.mode == "\22" then
    return nil, "Blockwise visual mode is not supported. Use charwise (v) or linewise (V)."
  end

  local lines = vim.api.nvim_buf_get_text(0, bounds.srow, bounds.scol, bounds.erow, bounds.end_col, {})
  local text = table.concat(lines, "\n")
  if text == "" then
    return nil, "No text selected. Select text in visual mode and try again."
  end

  return text
end

local function persist_state(cfg)
  if not cfg.persist_target then
    return
  end
  local ok, err = state.save(cfg.state_path, {
    target_lang = cfg.target_lang,
    engine = cfg.engine,
  })
  if not ok then
    notify(err, vim.log.levels.WARN)
  end
end

local function resolve_current_provider_or_notify(cfg)
  local provider, provider_err = resolve_provider_by_engine(cfg.engine)
  if not provider then
    notify(provider_err, vim.log.levels.ERROR)
    return nil
  end
  return provider
end

local function set_target_language(code)
  local cfg = ensure_setup()
  local provider = resolve_current_provider_or_notify(cfg)
  if not provider then
    return
  end

  local normalized = normalize_target_for_provider(provider, code)
  if not normalized then
    notify("Invalid target language code.", vim.log.levels.ERROR)
    return
  end
  if not is_target_supported_for_provider(provider, normalized) then
    notify(
      ("Unsupported target language '%s' for %s."):format(normalized, resolve_provider_label(cfg)),
      vim.log.levels.ERROR
    )
    return
  end

  cfg.target_lang = normalized
  invalidate_active_translation()
  persist_state(cfg)
  notify(("Target language: %s"):format(cfg.target_lang))
end

local function set_translation_engine(engine)
  local cfg = ensure_setup()
  local normalized = normalize.lower_name(engine)
  if not normalized then
    notify("Invalid engine name.", vim.log.levels.ERROR)
    return
  end

  local provider, provider_err = resolve_provider_by_engine(normalized)
  if not provider then
    notify(provider_err, vim.log.levels.ERROR)
    return
  end

  local previous_engine = cfg.engine
  local previous_target = cfg.target_lang
  cfg.engine = normalized

  local next_target = normalize_with_fallback_target(cfg, provider, previous_target)
  if not next_target then
    cfg.engine = previous_engine
    cfg.target_lang = previous_target
    notify("Failed to normalize target language for selected engine.", vim.log.levels.ERROR)
    return
  end

  cfg.target_lang = next_target
  invalidate_active_translation()
  persist_state(cfg)

  notify(("Translation engine: %s"):format(resolve_provider_label(cfg)))
end

local function select_target_from(items, prompt)
  local cfg = ensure_setup()

  vim.schedule(function()
    vim.ui.select(items, {
      prompt = prompt or "Select target language",
      format_item = function(item)
        if item.code == cfg.target_lang then
          return ("%s (%s) [current]"):format(item.name, item.code)
        end
        return ("%s (%s)"):format(item.name, item.code)
      end,
    }, function(choice)
      if choice then
        set_target_language(choice.code)
      end
    end)
  end)
end

local function select_engine_from(items)
  local cfg = ensure_setup()

  vim.schedule(function()
    vim.ui.select(items, {
      prompt = "Select translation engine",
      format_item = function(item)
        local label = resolve_provider_label(cfg, item)
        if item == cfg.engine then
          return ("%s (%s) [current]"):format(label, item)
        end
        return ("%s (%s)"):format(label, item)
      end,
    }, function(choice)
      if choice then
        set_translation_engine(choice)
      end
    end)
  end)
end

function M.setup(opts)
  local cfg = config_module.build(opts)
  local explicit_engine = has_explicit_engine_option(opts)
  if cfg.persist_target then
    local valid_state_path, state_path_err = state.validate_path(cfg.state_path)
    if not valid_state_path then
      error(("translate.nvim setup error: %s"):format(state_path_err))
    end
  end

  local saved = cfg.persist_target and state.load(cfg.state_path) or nil
  local restored_engine = nil
  if type(saved) == "table" then
    if not explicit_engine then
      local saved_engine = normalize.lower_name(saved.engine)
      if saved_engine and providers[saved_engine] then
        cfg.engine = saved_engine
        restored_engine = saved_engine
      end
    end
    if type(saved.target_lang) == "string" and saved.target_lang ~= "" then
      cfg.target_lang = saved.target_lang
    end
  end

  if not explicit_engine and not restored_engine and normalize.has_text(cfg.api_key) and normalize.has_text(cfg.google_api_key) then
    cfg.engine = "google"
  end

  local provider, provider_err = resolve_provider_by_engine(cfg.engine)
  if not provider then
    error(("translate.nvim setup error: %s"):format(provider_err))
  end

  local normalized_target = normalize_with_fallback_target(cfg, provider, cfg.target_lang)
  if not normalized_target then
    error(("translate.nvim setup error: failed to normalize target language for engine '%s'."):format(cfg.engine))
  end
  cfg.target_lang = normalized_target

  M._config = cfg
  M._target_cache = {}
  M._next_request_id = 0
  M._active_request_id = nil

  clear_keymaps()
  set_keymap("x", cfg.keymaps.translate_visual, function()
    require("translate").translate_visual()
  end, "Translate visual selection")
  set_keymap("n", cfg.keymaps.translate_file, function()
    require("translate").translate_file()
  end, "Translate entire file")
  set_keymap({ "n", "x" }, cfg.keymaps.select_target, function()
    require("translate").select_target()
  end, "Select target language")
  set_keymap({ "n", "x" }, cfg.keymaps.select_engine, function()
    require("translate").select_engine()
  end, "Select translation engine")

  return M
end

local function do_translate(cfg, text)
  local provider = resolve_current_provider_or_notify(cfg)
  if not provider then
    return
  end

  local request_id = begin_translation_request()
  local request_snapshot = build_translation_snapshot(cfg)
  local model_label = resolve_provider_label(cfg)

  provider.translate(request_snapshot, text, function(api_err, translated)
    if not is_active_translation_request(request_id) then
      return
    end
    if api_err then
      notify(api_err, vim.log.levels.ERROR)
      return
    end
    vim.schedule(function()
      if not is_active_translation_request(request_id) then
        return
      end
      ui.show_result(translated, cfg, { model = model_label })
    end)
  end)
end

function M.translate_visual()
  local cfg = ensure_setup()
  local text, err = get_visual_text()
  if not text then
    notify(err, vim.log.levels.ERROR)
    return
  end
  do_translate(cfg, text)
end

function M.translate_file()
  local cfg = ensure_setup()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local text = table.concat(lines, "\n")
  if text == "" then
    notify("Buffer is empty. Nothing to translate.", vim.log.levels.WARN)
    return
  end
  do_translate(cfg, text)
end

function M.select_target()
  local cfg = ensure_setup()
  local provider = resolve_current_provider_or_notify(cfg)
  if not provider then
    return
  end

  local cache_key = cfg.engine
  if M._target_cache[cache_key] then
    select_target_from(M._target_cache[cache_key], ("Select %s target language"):format(resolve_provider_label(cfg)))
    return
  end

  provider.target_languages(cfg, function(err, languages)
    if err then
      notify(err, vim.log.levels.ERROR)
      return
    end

    M._target_cache[cache_key] = languages
    select_target_from(languages, ("Select %s target language"):format(resolve_provider_label(cfg)))
  end)
end

function M.select_engine()
  local engines = available_engines()
  if #engines == 0 then
    notify("No translation engines are registered.", vim.log.levels.ERROR)
    return
  end
  select_engine_from(engines)
end

function M.set_target(code)
  set_target_language(code)
end

function M.set_engine(engine)
  set_translation_engine(engine)
end

function M.current_target()
  local cfg = ensure_setup()
  return cfg.target_lang
end

function M.current_engine()
  local cfg = ensure_setup()
  return cfg.engine
end

return M
