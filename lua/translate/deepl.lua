local M = {}
local normalize = require("translate.normalize")
local provider_common = require("translate.providers.common")
local MAX_TEXTS_PER_REQUEST = 50
local CURL_JSON_OPTIONS = {
  empty_stdout_message = "DeepL returned an empty response. Check API key and network connectivity.",
  decode_error_message = "Failed to parse DeepL response JSON. Verify API key and endpoint.",
}
local TARGET_LANG_ALIASES = {
  EN = "EN-US",
  PT = "PT-BR",
  ["ZH-CN"] = "ZH",
  ["ZH-TW"] = "ZH",
  ["ZH-HANS"] = "ZH",
  ["ZH-HANT"] = "ZH",
}

local SUPPORTED_TARGET_LANGUAGES = {
  AR = true,
  BG = true,
  CS = true,
  DA = true,
  DE = true,
  EL = true,
  ["EN-GB"] = true,
  ["EN-US"] = true,
  ES = true,
  ET = true,
  FI = true,
  FR = true,
  HE = true,
  HU = true,
  ID = true,
  IT = true,
  JA = true,
  KO = true,
  LT = true,
  LV = true,
  NB = true,
  NL = true,
  PL = true,
  ["PT-BR"] = true,
  ["PT-PT"] = true,
  RO = true,
  RU = true,
  SK = true,
  SL = true,
  SV = true,
  TH = true,
  TR = true,
  UK = true,
  VI = true,
  ZH = true,
}

---Normalize a target language code to a DeepL-compatible code.
---@param code string raw language code (e.g. "en", "zh-cn", "pt_BR")
---@return string normalized DeepL target language code
local function normalize_target(code)
  return provider_common.normalize_target_code(code, "EN-US", TARGET_LANG_ALIASES, SUPPORTED_TARGET_LANGUAGES)
end

---Check whether a language code is a supported DeepL target.
---@param code string language code
---@return boolean
local function is_target_supported(code)
  return provider_common.is_target_code_supported(code, "EN-US", TARGET_LANG_ALIASES, SUPPORTED_TARGET_LANGUAGES)
end

---Return the DeepL API base URL based on plan type.
---@param config table provider config with optional `free_api` flag
---@return string base URL
local function base_url(config)
  if config.free_api then
    return "https://api-free.deepl.com/v2"
  end
  return "https://api.deepl.com/v2"
end

---Build base curl args common to all DeepL requests.
---@param method string HTTP method ("GET" or "POST")
---@param url string full endpoint URL
---@return string[] base curl arguments
local function build_base_curl_args(method, url)
  return {
    "curl",
    "--silent",
    "--show-error",
    "--fail-with-body",
    "--request",
    method,
    url,
    "--config",
    "-",
  }
end

---Validate the API key and invoke on_done with an error if missing.
---@param config table provider config with `api_key`
---@param on_done fun(err: string?) callback
---@return boolean true if key is present
local function ensure_api_key(config, on_done)
  if not normalize.has_text(config.api_key) then
    on_done("DEEPL_AUTH_KEY is missing. Set it in env or call setup({ api_key = '...' }).")
    return false
  end
  return true
end

---Build curl arguments for a /translate request.
---@param config table request config with endpoint info
---@param body_path string path to URL-encoded POST body
---@return string[] curl arguments
local function build_translate_args(config, body_path)
  local endpoint = base_url(config) .. "/translate"
  local args = build_base_curl_args("POST", endpoint)
  table.insert(args, "--data-binary")
  table.insert(args, "@" .. body_path)

  return args
end

local function build_translate_body(config, lines)
  local fields = {
    { name = "target_lang", value = config.target_lang },
  }

  for _, line in ipairs(lines) do
    table.insert(fields, {
      name = "text",
      value = line,
    })
  end

  return provider_common.build_form_body(fields)
end

---Build the stdin config string for DeepL authorization header.
---@param api_key string DeepL API key
---@return string? curl config stdin content
local function build_auth_header_stdin(api_key)
  return provider_common.build_header_config_stdin({
    "Authorization: DeepL-Auth-Key " .. api_key,
  })
end

---Decode and validate a DeepL translate response.
---Extracts translated texts from the decoded JSON and validates the count.
---@param decoded table decoded JSON response
---@param expected_count number number of expected translation items
---@param start_index number starting index in the overall request (for error messages)
---@return string[]? texts extracted translated texts, or nil on error
---@return string? error_message error description if extraction failed
local function decode_translate_response(decoded, expected_count, start_index)
  if type(decoded.translations) ~= "table" then
    return nil, "DeepL response has no translations."
  end

  local texts = {}
  for i = 1, expected_count do
    local item = decoded.translations[i]
    if type(item) ~= "table" or type(item.text) ~= "string" then
      return nil, ("DeepL response is missing translated text at request index %d."):format(start_index + i - 1)
    end
    table.insert(texts, item.text)
  end

  return texts
end

---Translate text using the DeepL API.
---Handles chunking for large inputs (max 50 texts per request).
---@param config table provider config with `api_key`, `free_api`, `target_lang`
---@param text string text to translate (newline-separated lines)
---@param on_done fun(err: string?, result: string?) callback with error or translated text
function M.translate(config, text, on_done)
  if not ensure_api_key(config, on_done) then
    return
  end
  if not provider_common.validate_translate_text(text, on_done) then
    return
  end

  local request_config = {
    api_key = config.api_key,
    free_api = config.free_api,
    target_lang = normalize_target(config.target_lang),
  }
  if not SUPPORTED_TARGET_LANGUAGES[request_config.target_lang] then
    on_done(("Unsupported DeepL target language: %s"):format(tostring(request_config.target_lang)))
    return
  end

  local source_lines, request_lines, index_map, indent_map = provider_common.build_request_lines(text)
  local curl_opts = vim.tbl_extend("force", {}, CURL_JSON_OPTIONS, {
    stdin = build_auth_header_stdin(request_config.api_key),
  })

  return provider_common.translate_lines(source_lines, request_lines, index_map, indent_map, MAX_TEXTS_PER_REQUEST, "DeepL",
    function(chunk, start_idx, callback)
      local body_path, write_err = provider_common.write_temp_file("deepl-request", build_translate_body(request_config, chunk))
      if not body_path then
        callback(write_err)
        return nil
      end

      return provider_common.run_curl_json(build_translate_args(request_config, body_path), vim.tbl_extend("force", {}, curl_opts, {
        cleanup_paths = { body_path },
      }), function(err, decoded)
        if err then callback(err); return end
        local texts, decode_err = decode_translate_response(decoded, #chunk, start_idx)
        if not texts then callback(decode_err); return end
        callback(nil, texts)
      end)
    end,
    on_done
  )
end

---Fetch available DeepL target languages.
---@param config table provider config with `api_key` and `free_api`
---@param on_done fun(err: string?, languages: table[]?) callback with error or sorted language list
function M.target_languages(config, on_done)
  if not ensure_api_key(config, on_done) then
    return
  end

  local endpoint = base_url(config) .. "/languages?type=target"
  local args = build_base_curl_args("GET", endpoint)

  return provider_common.run_curl_json(args, vim.tbl_extend("force", {}, CURL_JSON_OPTIONS, {
    stdin = build_auth_header_stdin(config.api_key),
  }), function(err, decoded)
    if err then
      on_done(err)
      return
    end

    local languages = {}
    for _, item in ipairs(decoded) do
      if type(item) == "table" and type(item.language) == "string" then
        table.insert(languages, {
          code = item.language:upper(),
          name = type(item.name) == "string" and item.name or item.language,
        })
      end
    end

    table.sort(languages, function(a, b)
      return a.name < b.name
    end)

    if #languages == 0 then
      on_done("DeepL returned no target languages.")
      return
    end

    on_done(nil, languages)
  end)
end

---Normalize a target language code (public wrapper).
---@param code string language code
---@return string normalized code
function M.normalize_target(code)
  return normalize_target(code)
end

---Check if a target language is supported (public wrapper).
---@param code string language code
---@return boolean
function M.is_target_supported(code)
  return is_target_supported(code)
end

return M
