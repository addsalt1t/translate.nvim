local M = {}
local normalize = require("translate.normalize")
local provider_common = require("translate.providers.common")
local MAX_TEXTS_PER_REQUEST = 50
local CURL_JSON_OPTIONS = {
  empty_stdout_message = "Google Translate returned an empty response. Check network connectivity.",
  decode_error_message = "Failed to parse Google Translate response JSON.",
}

local TARGET_LANGUAGES = {
  { code = "AF", name = "Afrikaans" },
  { code = "SQ", name = "Albanian" },
  { code = "AM", name = "Amharic" },
  { code = "AR", name = "Arabic" },
  { code = "HY", name = "Armenian" },
  { code = "AZ", name = "Azerbaijani" },
  { code = "EU", name = "Basque" },
  { code = "BE", name = "Belarusian" },
  { code = "BN", name = "Bengali" },
  { code = "BS", name = "Bosnian" },
  { code = "BG", name = "Bulgarian" },
  { code = "CA", name = "Catalan" },
  { code = "CEB", name = "Cebuano" },
  { code = "ZH-CN", name = "Chinese (Simplified)" },
  { code = "ZH-TW", name = "Chinese (Traditional)" },
  { code = "CO", name = "Corsican" },
  { code = "HR", name = "Croatian" },
  { code = "CS", name = "Czech" },
  { code = "DA", name = "Danish" },
  { code = "NL", name = "Dutch" },
  { code = "EN", name = "English" },
  { code = "EO", name = "Esperanto" },
  { code = "ET", name = "Estonian" },
  { code = "TL", name = "Filipino" },
  { code = "FI", name = "Finnish" },
  { code = "FR", name = "French" },
  { code = "FY", name = "Frisian" },
  { code = "GL", name = "Galician" },
  { code = "KA", name = "Georgian" },
  { code = "DE", name = "German" },
  { code = "EL", name = "Greek" },
  { code = "GU", name = "Gujarati" },
  { code = "HT", name = "Haitian Creole" },
  { code = "HA", name = "Hausa" },
  { code = "HAW", name = "Hawaiian" },
  { code = "HE", name = "Hebrew" },
  { code = "HI", name = "Hindi" },
  { code = "HMN", name = "Hmong" },
  { code = "HU", name = "Hungarian" },
  { code = "IS", name = "Icelandic" },
  { code = "IG", name = "Igbo" },
  { code = "ID", name = "Indonesian" },
  { code = "GA", name = "Irish" },
  { code = "IT", name = "Italian" },
  { code = "JA", name = "Japanese" },
  { code = "JW", name = "Javanese" },
  { code = "KN", name = "Kannada" },
  { code = "KK", name = "Kazakh" },
  { code = "KM", name = "Khmer" },
  { code = "RW", name = "Kinyarwanda" },
  { code = "KO", name = "Korean" },
  { code = "KU", name = "Kurdish" },
  { code = "KY", name = "Kyrgyz" },
  { code = "LO", name = "Lao" },
  { code = "LA", name = "Latin" },
  { code = "LV", name = "Latvian" },
  { code = "LT", name = "Lithuanian" },
  { code = "LB", name = "Luxembourgish" },
  { code = "MK", name = "Macedonian" },
  { code = "MG", name = "Malagasy" },
  { code = "MS", name = "Malay" },
  { code = "ML", name = "Malayalam" },
  { code = "MT", name = "Maltese" },
  { code = "MI", name = "Maori" },
  { code = "MR", name = "Marathi" },
  { code = "MN", name = "Mongolian" },
  { code = "MY", name = "Myanmar (Burmese)" },
  { code = "NE", name = "Nepali" },
  { code = "NO", name = "Norwegian" },
  { code = "OR", name = "Odia" },
  { code = "PS", name = "Pashto" },
  { code = "FA", name = "Persian" },
  { code = "PL", name = "Polish" },
  { code = "PT", name = "Portuguese" },
  { code = "PA", name = "Punjabi" },
  { code = "RO", name = "Romanian" },
  { code = "RU", name = "Russian" },
  { code = "SM", name = "Samoan" },
  { code = "GD", name = "Scots Gaelic" },
  { code = "SR", name = "Serbian" },
  { code = "ST", name = "Sesotho" },
  { code = "SN", name = "Shona" },
  { code = "SD", name = "Sindhi" },
  { code = "SI", name = "Sinhala" },
  { code = "SK", name = "Slovak" },
  { code = "SL", name = "Slovenian" },
  { code = "SO", name = "Somali" },
  { code = "ES", name = "Spanish" },
  { code = "SU", name = "Sundanese" },
  { code = "SW", name = "Swahili" },
  { code = "SV", name = "Swedish" },
  { code = "TG", name = "Tajik" },
  { code = "TA", name = "Tamil" },
  { code = "TT", name = "Tatar" },
  { code = "TE", name = "Telugu" },
  { code = "TH", name = "Thai" },
  { code = "TR", name = "Turkish" },
  { code = "TK", name = "Turkmen" },
  { code = "UK", name = "Ukrainian" },
  { code = "UR", name = "Urdu" },
  { code = "UG", name = "Uyghur" },
  { code = "UZ", name = "Uzbek" },
  { code = "VI", name = "Vietnamese" },
  { code = "CY", name = "Welsh" },
  { code = "XH", name = "Xhosa" },
  { code = "YI", name = "Yiddish" },
  { code = "YO", name = "Yoruba" },
  { code = "ZU", name = "Zulu" },
}

local TARGET_LANGUAGE_SET = {}
for _, item in ipairs(TARGET_LANGUAGES) do
  TARGET_LANGUAGE_SET[item.code] = true
end

local ALIASES = {
  ["EN-US"] = "EN",
  ["EN-GB"] = "EN",
  ["PT-BR"] = "PT",
  ["PT-PT"] = "PT",
  ["ZH-HANS"] = "ZH-CN",
  ["ZH-HANT"] = "ZH-TW",
}

---Decode translated texts from the official Cloud Translation API response.
---@param decoded table Raw decoded JSON from the official endpoint
---@param expected_count integer Number of expected translated texts
---@return string[]|nil texts Array of translated texts, or nil on error
---@return string|nil err Error message if decoding failed
local function decode_official_translated_texts(decoded, expected_count)
  if type(decoded.data) ~= "table" then
    return nil, "Google Cloud response has no data field."
  end

  local translations = decoded.data.translations
  if type(translations) ~= "table" or #translations == 0 then
    return nil, "Google Cloud response has no translations."
  end

  if #translations < expected_count then
    return nil, ("Google Cloud response has %d translations, expected %d."):format(#translations, expected_count)
  end

  local texts = {}
  for i = 1, expected_count do
    local item = translations[i]
    if type(item) ~= "table" or type(item.translatedText) ~= "string" then
      return nil, ("Google Cloud response is missing translatedText at index %d."):format(i)
    end
    table.insert(texts, item.translatedText)
  end

  return texts
end

---Normalize a target language code to the canonical form used by Google.
---@param code string Raw language code (e.g. "en-US", "zh_Hans")
---@return string normalized Canonical uppercase language code (e.g. "EN", "ZH-CN")
local function normalize_target(code)
  return provider_common.normalize_target_code(code, "EN", ALIASES, TARGET_LANGUAGE_SET)
end

---Check whether a language code is supported by Google Translate.
---@param code string Language code to check
---@return boolean supported True if the normalized code is in the supported set
local function is_target_supported(code)
  return provider_common.is_target_code_supported(code, "EN", ALIASES, TARGET_LANGUAGE_SET)
end

---Build base curl args common to all Google requests.
---@param method string HTTP method ("GET" or "POST")
---@param url string Full endpoint URL
---@return string[] args Base curl arguments
local function build_base_curl_args(method, url)
  local args = { "curl", "--silent", "--show-error", "--fail-with-body" }
  if method == "GET" then
    table.insert(args, "--get")
  else
    table.insert(args, "--request")
    table.insert(args, method)
  end
  table.insert(args, url)
  return args
end

---Build curl arguments for the official Cloud Translation API translate endpoint.
---@param body_path string path to URL-encoded POST body
---@param target_lang string Normalized target language code
---@return string[] args Curl command arguments
local function build_official_translate_args(body_path, target_lang)
  local args = build_base_curl_args("POST", "https://translation.googleapis.com/language/translate/v2")
  vim.list_extend(args, {
    "--config",
    "-",
    "--data-binary",
    "@" .. body_path,
  })

  return args
end

local function build_official_translate_body(lines, target_lang)
  local fields = {
    { name = "target", value = target_lang:lower() },
    { name = "format", value = "text" },
  }

  for _, line in ipairs(lines) do
    table.insert(fields, {
      name = "q",
      value = line,
    })
  end

  return provider_common.build_form_body(fields)
end

---Build curl arguments for the official Cloud Translation API languages endpoint.
---@return string[] args Curl command arguments
local function build_official_languages_args()
  local args = build_base_curl_args("GET", "https://translation.googleapis.com/language/translate/v2/languages")
  vim.list_extend(args, { "--config", "-", "--data-urlencode", "target=en" })
  return args
end

---Build stdin content for curl --config with an API key header.
---@param api_key string Google API key
---@return string stdin Curl config stdin string containing the header
local function build_api_key_header_stdin(api_key)
  return provider_common.build_header_config_stdin({
    "X-Goog-Api-Key: " .. api_key,
  })
end

---Decode target languages from the official Cloud Translation API response.
---@param decoded table Raw decoded JSON from the languages endpoint
---@return table[]|nil languages Array of {code, name} tables, or nil on error
---@return string|nil err Error message if decoding failed
local function decode_official_target_languages(decoded)
  if type(decoded.data) ~= "table" then
    return nil, "Google Cloud response has no data field."
  end

  local items = decoded.data.languages
  if type(items) ~= "table" then
    return nil, "Google Cloud response has no languages."
  end

  local languages = {}
  local seen = {}

  for _, item in ipairs(items) do
    if type(item) == "table" and type(item.language) == "string" then
      local code = normalize_target(item.language)
      if not seen[code] then
        local name = type(item.name) == "string" and item.name ~= "" and item.name or code
        table.insert(languages, {
          code = code,
          name = name,
        })
        seen[code] = true
      end
    end
  end

  table.sort(languages, function(a, b)
    return a.name < b.name
  end)

  if #languages == 0 then
    return nil, "Google Cloud returned no target languages."
  end

  return languages
end

---Validate the API key and invoke on_done with an error if missing.
---@param config table Provider config with `google_api_key`
---@param on_done fun(err: string?) Callback
---@return string|nil api_key The trimmed API key, or nil if missing
local function ensure_api_key(config, on_done)
  local api_key = normalize.trim_to_nil(config.google_api_key)
  if not api_key then
    on_done("Google API key is missing. Set GOOGLE_TRANSLATE_API_KEY or GOOGLE_API_KEY in env, or call setup({ google_api_key = '...' }).")
    return nil
  end
  return api_key
end

---Normalize a target language code (public wrapper).
---@param code string Raw language code
---@return string normalized Canonical uppercase language code
function M.normalize_target(code)
  return normalize_target(code)
end

---Check whether a language code is supported (public wrapper).
---@param code string Language code to check
---@return boolean supported True if the normalized code is in the supported set
function M.is_target_supported(code)
  return is_target_supported(code)
end

---Translate text using Google Cloud Translation API.
---@param config table Configuration with target_lang, google_api_key fields
---@param text string The text to translate
---@param on_done fun(err: string|nil, translated: string|nil) Completion callback
function M.translate(config, text, on_done)
  local api_key = ensure_api_key(config, on_done)
  if not api_key then return end

  if not provider_common.validate_translate_text(text, on_done) then
    return
  end

  local source_lines, request_lines, index_map, indent_map = provider_common.build_request_lines(text)
  local target_lang = normalize_target(config.target_lang)

  if not TARGET_LANGUAGE_SET[target_lang] then
    on_done(("Unsupported Google target language: %s"):format(tostring(target_lang)))
    return
  end

  local curl_opts = vim.tbl_extend("force", {}, CURL_JSON_OPTIONS, {
    stdin = build_api_key_header_stdin(api_key),
  })

  return provider_common.translate_lines(source_lines, request_lines, index_map, indent_map, MAX_TEXTS_PER_REQUEST, "Google",
    function(chunk, _start_idx, callback)
      local body_path, write_err = provider_common.write_temp_file("google-request", build_official_translate_body(chunk, target_lang))
      if not body_path then
        callback(write_err)
        return nil
      end

      local args = build_official_translate_args(body_path, target_lang)
      return provider_common.run_curl_json(args, vim.tbl_extend("force", {}, curl_opts, {
        cleanup_paths = { body_path },
      }), function(err, decoded)
        if err then callback(err); return end
        local translated_texts, decode_err = decode_official_translated_texts(decoded, #chunk)
        if not translated_texts then callback(decode_err); return end
        callback(nil, translated_texts)
      end)
    end,
    on_done
  )
end

---Fetch available target languages from Google Translate.
---@param config table|nil Configuration with google_api_key field
---@param on_done fun(err: string|nil, languages: table[]|nil) Completion callback
function M.target_languages(config, on_done)
  local api_key = ensure_api_key(config or {}, on_done)
  if not api_key then return end

  return provider_common.run_curl_json(build_official_languages_args(), vim.tbl_extend("force", {}, CURL_JSON_OPTIONS, {
    stdin = build_api_key_header_stdin(api_key),
  }), function(err, decoded)
    if err then
      on_done(err)
      return
    end

    local languages, parse_err = decode_official_target_languages(decoded)
    if not languages then
      on_done(parse_err)
      return
    end

    on_done(nil, languages)
  end)
end

return M
