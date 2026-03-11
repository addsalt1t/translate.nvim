local config_module = require("translate.config")
local normalize = require("translate.normalize")
local picker = require("translate.picker")
local selection = require("translate.selection")
local state = require("translate.state")
local ui = require("translate.ui")

local providers = {
  deepl = require("translate.deepl"),
  google = require("translate.google"),
}

local M = {
  _config = nil,
  _target_cache = {},
  _pending_target_lookups = {},
  _keymaps = {},
  _next_request_id = 0,
  _next_target_lookup_id = 0,
  _active_request_id = nil,
  _active_request_controller = nil,
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
  return type(opts) == "table" and normalize.lower_name(opts.engine) ~= nil
end

local function notify_deprecated_float_options(opts)
  local float = type(opts) == "table" and type(opts.float) == "table" and opts.float or nil
  if not float then
    return
  end

  if float.max_width_ratio ~= nil then
    notify("float.max_width_ratio is deprecated. Use float.width_ratio instead.", vim.log.levels.WARN)
  end
  if float.max_height_ratio ~= nil then
    notify("float.max_height_ratio is deprecated. Use float.height_ratio instead.", vim.log.levels.WARN)
  end
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
  local controller = M._active_request_controller
  M._active_request_controller = nil
  if controller and type(controller.kill) == "function" then
    pcall(controller.kill, controller, 15)
  end
end

local function begin_translation_request()
  M._next_request_id = M._next_request_id + 1
  M._active_request_id = M._next_request_id
  return M._next_request_id
end

local function begin_target_lookup(engine)
  local current = M._pending_target_lookups[engine]
  if current then
    return nil
  end

  M._next_target_lookup_id = M._next_target_lookup_id + 1
  M._pending_target_lookups[engine] = M._next_target_lookup_id
  return M._next_target_lookup_id
end

local function finish_target_lookup(engine, lookup_id)
  if M._pending_target_lookups[engine] ~= lookup_id then
    return false
  end

  M._pending_target_lookups[engine] = nil
  return true
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

local function update_runtime_state(cfg, changes)
  if changes.engine then
    cfg.engine = changes.engine
  end
  if changes.target_lang then
    cfg.target_lang = changes.target_lang
  end
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

local function apply_runtime_state(cfg, changes)
  update_runtime_state(cfg, changes)
  invalidate_active_translation()
  persist_state(cfg)
end

local function resolve_current_provider_or_notify(cfg)
  local provider, provider_err = resolve_provider_by_engine(cfg.engine)
  if not provider then
    notify(provider_err, vim.log.levels.ERROR)
    return nil
  end
  return provider
end

local function resolve_target_change(cfg, provider, code)
  local normalized = normalize_target_for_provider(provider, code)
  if not normalized then
    return nil, "Invalid target language code."
  end
  if not is_target_supported_for_provider(provider, normalized) then
    return nil, ("Unsupported target language '%s' for %s."):format(normalized, resolve_provider_label(cfg))
  end

  return normalized
end

local function resolve_engine_change(cfg, engine)
  local normalized = normalize.lower_name(engine)
  if not normalized then
    return nil, "Invalid engine name."
  end

  local provider, provider_err = resolve_provider_by_engine(normalized)
  if not provider then
    return nil, provider_err
  end

  local next_target = normalize_with_fallback_target(cfg, provider, cfg.target_lang)
  if not next_target then
    return nil, "Failed to normalize target language for selected engine."
  end

  return {
    engine = normalized,
    target_lang = next_target,
  }
end

local function set_target_language(code)
  local cfg = ensure_setup()
  local provider = resolve_current_provider_or_notify(cfg)
  if not provider then
    return
  end

  local normalized, err = resolve_target_change(cfg, provider, code)
  if not normalized then
    notify(err, vim.log.levels.ERROR)
    return
  end

  apply_runtime_state(cfg, { target_lang = normalized })
  notify(("Target language: %s"):format(cfg.target_lang))
end

local function set_translation_engine(engine)
  local cfg = ensure_setup()
  local next_state, err = resolve_engine_change(cfg, engine)
  if not next_state then
    notify(err, vim.log.levels.ERROR)
    return
  end

  apply_runtime_state(cfg, next_state)
  notify(("Translation engine: %s"):format(resolve_provider_label(cfg)))
end

local function target_picker_prompt(cfg)
  return ("Select %s target language"):format(resolve_provider_label(cfg))
end

local function show_target_picker(items)
  local cfg = ensure_setup()

  picker.open(items, {
    prompt = target_picker_prompt(cfg),
    format_item = picker.target_formatter(cfg.target_lang),
    on_choice = function(choice)
      set_target_language(choice.code)
    end,
  })
end

local function show_engine_picker(items)
  local cfg = ensure_setup()

  picker.open(items, {
    prompt = "Select translation engine",
    format_item = picker.engine_formatter(cfg.engine, function(engine)
      return resolve_provider_label(cfg, engine)
    end),
    on_choice = set_translation_engine,
  })
end

local function register_keymaps(cfg)
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
end

local function restore_saved_state(cfg, explicit_engine)
  local saved = cfg.persist_target and state.load(cfg.state_path) or nil
  local restored_engine = false

  if type(saved) == "table" then
    if not explicit_engine then
      local saved_engine = normalize.lower_name(saved.engine)
      if saved_engine and providers[saved_engine] then
        cfg.engine = saved_engine
        restored_engine = true
      end
    end
    if type(saved.target_lang) == "string" and saved.target_lang ~= "" then
      cfg.target_lang = saved.target_lang
    end
  end

  return restored_engine
end

local function choose_default_engine(cfg, explicit_engine, restored_engine)
  if explicit_engine or restored_engine then
    return
  end
  if normalize.has_text(cfg.api_key) and normalize.has_text(cfg.google_api_key) then
    cfg.engine = "google"
  end
end

local function normalize_setup_state(cfg)
  local provider, provider_err = resolve_provider_by_engine(cfg.engine)
  if not provider then
    error(("translate.nvim setup error: %s"):format(provider_err))
  end

  local normalized_target = normalize_with_fallback_target(cfg, provider, cfg.target_lang)
  if not normalized_target then
    error(("translate.nvim setup error: failed to normalize target language for engine '%s'."):format(cfg.engine))
  end

  cfg.target_lang = normalized_target
end

local function activate_config(cfg)
  invalidate_active_translation()
  M._config = cfg
  M._target_cache = {}
  M._pending_target_lookups = {}
  M._next_request_id = 0
  M._next_target_lookup_id = 0
  M._active_request_id = nil
  M._active_request_controller = nil
  register_keymaps(cfg)
end

function M.setup(opts)
  notify_deprecated_float_options(opts)
  local cfg = config_module.build(opts)
  local explicit_engine = has_explicit_engine_option(opts)
  if cfg.persist_target then
    local valid_state_path, state_path_err = state.validate_path(cfg.state_path)
    if not valid_state_path then
      error(("translate.nvim setup error: %s"):format(state_path_err))
    end
  end

  local restored_engine = restore_saved_state(cfg, explicit_engine)
  choose_default_engine(cfg, explicit_engine, restored_engine)
  normalize_setup_state(cfg)
  activate_config(cfg)

  return M
end

local function do_translate(cfg, text)
  local provider = resolve_current_provider_or_notify(cfg)
  if not provider then
    return
  end

  local source_win = vim.api.nvim_get_current_win()
  invalidate_active_translation()
  local request_id = begin_translation_request()
  local request_snapshot = build_translation_snapshot(cfg)
  local model_label = resolve_provider_label(cfg)
  local request_finished = false

  local controller = provider.translate(request_snapshot, text, function(api_err, translated)
    request_finished = true
    if is_active_translation_request(request_id) then
      M._active_request_controller = nil
    end
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
      ui.show_result(translated, cfg, {
        model = model_label,
        source_win = source_win,
      })
    end)
  end)

  if not request_finished and is_active_translation_request(request_id) then
    M._active_request_controller = controller
  else
    M._active_request_controller = nil
  end
end

function M.translate_visual()
  local cfg = ensure_setup()
  local text, err = selection.get_visual_text()
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
    show_target_picker(M._target_cache[cache_key])
    return
  end

  local lookup_id = begin_target_lookup(cache_key)
  if not lookup_id then
    return
  end

  provider.target_languages(cfg, function(err, languages)
    if not finish_target_lookup(cache_key, lookup_id) then
      return
    end

    local current_cfg = ensure_setup()
    if err then
      if current_cfg.engine == cache_key then
        notify(err, vim.log.levels.ERROR)
      end
      return
    end

    M._target_cache[cache_key] = languages
    if current_cfg.engine ~= cache_key then
      return
    end

    show_target_picker(languages)
  end)
end

function M.select_engine()
  local engines = available_engines()
  if #engines == 0 then
    notify("No translation engines are registered.", vim.log.levels.ERROR)
    return
  end
  show_engine_picker(engines)
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
