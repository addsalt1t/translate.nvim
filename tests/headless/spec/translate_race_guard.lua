local M = {}

local async_case = require("tests.headless.helpers.async_case")
local mock = require("tests.headless.helpers.mock_system")

local function make_deepl_response(prefix, count)
  local items = {}
  for i = 1, count do
    table.insert(items, ('{"text":"%s%d"}'):format(prefix, i))
  end
  return ('{"translations":[%s]}'):format(table.concat(items, ","))
end

local function reset_to_regular_window()
  local current_config = vim.api.nvim_win_get_config(0)
  if type(current_config.relative) == "string" and current_config.relative ~= "" then
    pcall(vim.api.nvim_win_close, 0, true)
  end
  vim.cmd("silent! only")
end

function M.run()
  local deepl = require("translate.deepl")

  local original_system = vim.system
  local cfg = {
    api_key = "dummy",
    free_api = true,
    target_lang = "KO",
  }

  local calls = {}
  local call_index = 0

  vim.system = function(args, _, on_done)
    call_index = call_index + 1
    table.insert(calls, vim.deepcopy(args))

    local text_count = 0
    local target_lang
    for _, value in ipairs(args) do
      if type(value) == "string" and string.sub(value, 1, 1) == "@" then
        local body = table.concat(vim.fn.readfile(string.sub(value, 2)), "\n")
        local matched_target = string.match(body, "target_lang=([^&]+)")
        if matched_target then
          target_lang = matched_target
        end
        text_count = select(2, string.gsub(body, "text=", ""))
      end
    end
    assert(target_lang ~= nil, "target_lang is missing in request")

    if call_index == 1 then
      cfg.target_lang = "JA"
    end

    local body = make_deepl_response(("C%d-"):format(call_index), text_count)
    vim.schedule(function()
      on_done({
        code = 0,
        stdout = body,
        stderr = "",
      })
    end)

    return {
      wait = function()
        return {}
      end,
    }
  end

  local lines = {}
  for i = 1, 51 do
    table.insert(lines, ("line-%d"):format(i))
  end
  local input = table.concat(lines, "\n")

  local err_msg = async_case.await_callback("deepl.translate callback", 1500, function(done)
    deepl.translate(cfg, input, function(err)
      done(err)
    end)
  end)

  vim.system = original_system

  assert(err_msg == nil, ("deepl.translate failed: %s"):format(tostring(err_msg)))
  assert(#calls == 2, ("expected 2 chunk calls, got %d"):format(#calls))

  local first = table.concat(calls[1], " ")
  local second = table.concat(calls[2], " ")
  assert(string.find(first, "@", 1, true), "first chunk should send a body tempfile")
  assert(string.find(second, "@", 1, true), "second chunk should send a body tempfile")

  local translate = require("translate")
  local deepl_provider = require("translate.deepl")
  local original_translate = deepl_provider.translate
  local original_notify = vim.notify

  vim.notify = function() end

  deepl_provider.translate = function(_, _, on_done)
    if not M._request_count then
      M._request_count = 0
    end
    M._request_count = M._request_count + 1
    local current = M._request_count
    local delay = current == 1 and 60 or 10
    local value = current == 1 and "first-result" or "second-result"
    vim.defer_fn(function()
      on_done(nil, value)
    end, delay)
  end

  translate.setup({
    engine = "deepl",
    api_key = "dummy",
    persist_target = false,
    target_lang = "KO",
    float = {
      border = "rounded",
      width = 30,
      height = 6,
      min_width = 20,
      min_height = 4,
      inherit_view = false,
      center_vertical = false,
      winhighlight = "NormalFloat:Normal",
    },
  })

  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello world" })
  vim.api.nvim_buf_set_mark(buf, "<", 1, 0, {})
  vim.api.nvim_buf_set_mark(buf, ">", 1, 11, {})

  translate.translate_visual()
  translate.translate_visual()

  local ui_ok = vim.wait(1500, function()
    local win = vim.api.nvim_get_current_win()
    local lines_now = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
    local content = table.concat(lines_now, "\n")
    return string.find(content, "second-result", 1, true) ~= nil
  end, 20)

  deepl_provider.translate = original_translate
  vim.notify = original_notify
  M._request_count = nil

  assert(ui_ok, "stale request guard did not keep the latest result")

  mock.with_mock_system({
    {
      code = 0,
      stdout = make_deepl_response("slow-", 1),
      stderr = "",
      delay_ms = 80,
    },
    {
      code = 0,
      stdout = make_deepl_response("fast-", 1),
      stderr = "",
      delay_ms = 5,
    },
  }, function(_, records)
    translate.setup({
      engine = "deepl",
      api_key = "dummy",
      persist_target = false,
      target_lang = "KO",
      float = {
        border = "rounded",
        width = 30,
        height = 6,
        min_width = 20,
        min_height = 4,
        inherit_view = false,
        center_vertical = false,
        winhighlight = "NormalFloat:Normal",
      },
    })

    local buf2 = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(0, buf2)
    vim.api.nvim_buf_set_lines(buf2, 0, -1, false, { "hello world" })
    vim.api.nvim_buf_set_mark(buf2, "<", 1, 0, {})
    vim.api.nvim_buf_set_mark(buf2, ">", 1, 11, {})

    translate.translate_visual()
    translate.translate_visual()

    local cancelled = vim.wait(1000, function()
      return records[1] and records[1].killed
    end, 20)

    assert(cancelled, "starting a new translation should cancel the previous in-flight curl request")
  end)

  local original_list = vim.wo.list
  deepl_provider.translate = function(_, _, on_done)
    vim.defer_fn(function()
      on_done(nil, "anchored-result")
    end, 60)

    return {
      kill = function() end,
    }
  end

  translate.setup({
    engine = "deepl",
    api_key = "dummy",
    persist_target = false,
    target_lang = "KO",
    float = {
      border = "rounded",
      width = 30,
      height = 6,
      min_width = 20,
      min_height = 4,
      inherit_view = true,
      center_vertical = false,
      winhighlight = "NormalFloat:Normal",
    },
  })

  reset_to_regular_window()
  vim.cmd("enew")
  local source_win = vim.api.nvim_get_current_win()
  vim.wo[source_win].list = true
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello world" })
  vim.cmd("vsplit")
  local other_win = vim.api.nvim_get_current_win()
  vim.wo[other_win].list = false
  vim.api.nvim_set_current_win(source_win)
  vim.api.nvim_buf_set_mark(0, "<", 1, 0, {})
  vim.api.nvim_buf_set_mark(0, ">", 1, 11, {})

  local original_mode = vim.fn.mode
  local original_getpos = vim.fn.getpos
  vim.fn.mode = function()
    return "v"
  end
  vim.fn.getpos = function(mark)
    if mark == "v" then
      return { 0, 1, 1, 0 }
    end
    return { 0, 1, 11, 0 }
  end

  translate.translate_visual()
  vim.api.nvim_set_current_win(other_win)

  local anchored = vim.wait(1500, function()
    local win = vim.api.nvim_get_current_win()
    local cfg = vim.api.nvim_win_get_config(win)
    return cfg.relative == "editor" and vim.wo[win].list == true
  end, 20)

  vim.fn.mode = original_mode
  vim.fn.getpos = original_getpos
  vim.wo.list = original_list
  deepl_provider.translate = original_translate

  assert(anchored, "async translation result should inherit view options from the original source window")
  reset_to_regular_window()
end

return M
