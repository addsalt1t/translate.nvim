local M = {}

local function has_event(events, level, pattern)
  for _, event in ipairs(events) do
    if event.level == level and string.find(event.message, pattern, 1, true) then
      return true
    end
  end
  return false
end

function M.run()
  local health = require("translate.health")
  assert(type(health.check) == "function", "translate.health.check must be a function")

  local events = {}
  local original_health = vim.health
  local original_executable = vim.fn.executable
  local original_has = vim.fn.has
  local original_deepl = vim.env.DEEPL_AUTH_KEY
  local original_google_translate = vim.env.GOOGLE_TRANSLATE_API_KEY
  local original_google = vim.env.GOOGLE_API_KEY

  vim.health = {
    start = function(message)
      table.insert(events, { level = "start", message = message })
    end,
    ok = function(message)
      table.insert(events, { level = "ok", message = message })
    end,
    warn = function(message)
      table.insert(events, { level = "warn", message = message })
    end,
    error = function(message)
      table.insert(events, { level = "error", message = message })
    end,
  }

  vim.fn.executable = function(binary)
    if binary == "curl" then
      return 1
    end
    return original_executable(binary)
  end

  vim.fn.has = function(feature)
    if feature == "nvim-0.10" then
      return 1
    end
    return original_has(feature)
  end

  vim.env.DEEPL_AUTH_KEY = nil
  vim.env.GOOGLE_TRANSLATE_API_KEY = nil
  vim.env.GOOGLE_API_KEY = nil

  local ok, run_err = pcall(health.check)

  vim.env.DEEPL_AUTH_KEY = original_deepl
  vim.env.GOOGLE_TRANSLATE_API_KEY = original_google_translate
  vim.env.GOOGLE_API_KEY = original_google
  vim.fn.has = original_has
  vim.fn.executable = original_executable
  vim.health = original_health

  assert(ok, ("translate.health.check should not throw: %s"):format(tostring(run_err)))
  assert(has_event(events, "start", "translate.nvim"), "health report should start with translate.nvim section")
  assert(has_event(events, "ok", "Neovim version"), "health report should include Neovim version check")
  assert(has_event(events, "ok", "curl"), "health report should include curl check")
  assert(
    has_event(events, "warn", "DEEPL_AUTH_KEY"),
    "health report should warn when DeepL key is not set in environment"
  )
  assert(
    has_event(events, "warn", "GOOGLE_TRANSLATE_API_KEY"),
    "health report should mention Google API key env when key is not set"
  )
end

return M
