local M = {}
local normalize = require("translate.normalize")

---Normalize a target language code using provider-specific data.
---@param code any Raw language code (e.g. "en", "zh-cn", "pt_BR")
---@param default string Fallback code when input is nil/empty (e.g. "EN-US", "EN")
---@param aliases table Provider-specific alias lookup table
---@param supported table Boolean keyset of supported language codes
---@return string normalized Canonical uppercase language code
function M.normalize_target_code(code, default, aliases, supported)
  local normalized = normalize.upper_code(code) or default
  normalized = normalized:gsub("_", "-")
  normalized = aliases[normalized] or normalized
  if supported[normalized] then
    return normalized
  end
  local base = normalized:match("^([A-Z][A-Z])%-")
  if base and supported[base] then
    return base
  end
  return normalized
end

---Check whether a language code is supported using provider-specific data.
---@param code any Language code to check
---@param default string Fallback code
---@param aliases table Provider-specific alias lookup table
---@param supported table Boolean keyset of supported language codes
---@return boolean supported True if the normalized code is in the supported set
function M.is_target_code_supported(code, default, aliases, supported)
  return supported[M.normalize_target_code(code, default, aliases, supported)] == true
end

function M.run_curl_json(args, opts, on_done)
  opts = opts or {}
  local empty_stdout_message = opts.empty_stdout_message or "Response is empty."
  local decode_error_message = opts.decode_error_message or "Failed to parse response JSON."
  local stdin = type(opts.stdin) == "string" and opts.stdin ~= "" and opts.stdin or nil

  vim.system(args, { text = true, stdin = stdin }, function(result)
    local stderr = vim.trim(result.stderr or "")
    local stdout = vim.trim(result.stdout or "")

    if result.code ~= 0 then
      local message = stderr ~= "" and stderr or stdout
      if message == "" then
        message = ("curl exited with code %d"):format(result.code)
      end
      on_done(message)
      return
    end

    if stdout == "" then
      on_done(empty_stdout_message)
      return
    end

    local ok, decoded = pcall(vim.json.decode, stdout)
    if not ok or type(decoded) ~= "table" then
      on_done(decode_error_message)
      return
    end

    on_done(nil, decoded)
  end)
end

local function escape_curl_config_value(value)
  return value:gsub("\\", "\\\\"):gsub('"', '\\"')
end

function M.build_header_config_stdin(headers)
  if type(headers) ~= "table" then
    return nil
  end

  local lines = {}
  for _, header in ipairs(headers) do
    if type(header) == "string" and header ~= "" then
      table.insert(lines, ('header = "%s"'):format(escape_curl_config_value(header)))
    end
  end

  if #lines == 0 then
    return nil
  end

  return table.concat(lines, "\n") .. "\n"
end

function M.split_lines(text)
  return vim.split(text, "\n", { plain = true, trimempty = false })
end

function M.build_request_lines(text)
  local source_lines = M.split_lines(text)
  local request_lines = {}
  local index_map = {}
  local indent_map = {}

  for source_index, line in ipairs(source_lines) do
    if line ~= "" then
      local indent, content = line:match("^(%s*)(.*)")
      table.insert(request_lines, content)
      table.insert(index_map, source_index)
      table.insert(indent_map, indent)
    end
  end

  return source_lines, request_lines, index_map, indent_map
end

---Dispatch items in parallel chunks, collect results in order, and invoke on_done.
---@param items any[] Items to process (e.g. request_lines)
---@param max_per_chunk integer Maximum items per chunk
---@param run_chunk fun(chunk: any[], start_idx: integer, callback: fun(err: string?, texts: string[]?)) Per-chunk handler
---@param on_done fun(err: string?, all_texts: string[]?) Final callback with ordered results
function M.dispatch_parallel_chunks(items, max_per_chunk, run_chunk, on_done)
  local num_chunks = math.ceil(#items / max_per_chunk)
  local results = {}
  local pending = num_chunks
  local failed = false

  for chunk_id = 1, num_chunks do
    local start_idx = (chunk_id - 1) * max_per_chunk + 1
    local stop_idx = math.min(chunk_id * max_per_chunk, #items)
    local chunk = vim.list_slice(items, start_idx, stop_idx)

    run_chunk(chunk, start_idx, function(err, texts)
      if failed then return end
      if err then
        failed = true
        on_done(err)
        return
      end
      if #texts ~= #chunk then
        failed = true
        on_done(("Response returned %d translations for %d lines."):format(#texts, #chunk))
        return
      end
      results[chunk_id] = texts
      pending = pending - 1
      if pending == 0 then
        local all_texts = {}
        for i = 1, num_chunks do
          vim.list_extend(all_texts, results[i])
        end
        on_done(nil, all_texts)
      end
    end)
  end
end

local function translated_text(item)
  if type(item) == "string" then
    return item
  end
  return nil
end

function M.merge_translated_lines(source_lines, translations, index_map, provider_name, indent_map)
  local merged = vim.list_extend({}, source_lines)
  local name = type(provider_name) == "string" and provider_name ~= "" and provider_name or "Provider"

  for i, source_index in ipairs(index_map) do
    local text = translated_text(translations[i])
    if not text then
      return nil, ("%s response is missing translation for line %d."):format(name, source_index)
    end
    local prefix = indent_map and indent_map[i] or ""
    merged[source_index] = prefix .. text
  end

  return table.concat(merged, "\n")
end

---Validate that text is a non-empty string, calling on_done with an error if not.
---@param text any Value to validate
---@param on_done fun(err: string) Error callback
---@return boolean valid True if text is valid for translation
function M.validate_translate_text(text, on_done)
  if type(text) ~= "string" or text == "" then
    on_done("No text provided for translation.")
    return false
  end
  return true
end

---Translate lines via parallel chunked dispatch and merge results.
---Handles the empty-request-lines shortcut and the final merge step.
---@param source_lines string[] Original lines (including blanks)
---@param request_lines string[] Non-blank lines to translate
---@param index_map integer[] Mapping from request index to source index
---@param indent_map string[] Leading whitespace stripped from each request line
---@param max_per_chunk integer Maximum lines per parallel request
---@param provider_name string Provider name for error messages
---@param run_chunk fun(chunk: string[], start_idx: integer, callback: fun(err: string?, texts: string[]?)) Per-chunk handler
---@param on_done fun(err: string?, translated: string?) Final callback
function M.translate_lines(source_lines, request_lines, index_map, indent_map, max_per_chunk, provider_name, run_chunk, on_done)
  if #request_lines == 0 then
    on_done(nil, table.concat(source_lines, "\n"))
    return
  end

  M.dispatch_parallel_chunks(request_lines, max_per_chunk,
    run_chunk,
    function(err, all_texts)
      if err then on_done(err); return end
      local translated, merge_err = M.merge_translated_lines(
        source_lines, all_texts, index_map, provider_name, indent_map
      )
      if not translated then on_done(merge_err); return end
      on_done(nil, translated)
    end
  )
end

return M
