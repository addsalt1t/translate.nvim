local M = {}
local normalize = require("translate.normalize")

---@param name string Environment variable name
---@return boolean
local function has_env_key(name)
  return normalize.has_text(vim.env[name])
end

---@return nil
function M.check()
  vim.health.start("translate.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim version is compatible (>= 0.10).")
  else
    vim.health.error("Neovim 0.10+ is required because translate.nvim uses vim.system().")
  end

  if vim.fn.executable("curl") == 1 then
    vim.health.ok("curl is available.")
  else
    vim.health.error("curl is required. Install curl and ensure it is available on PATH.")
  end

  if has_env_key("DEEPL_AUTH_KEY") then
    vim.health.ok("DEEPL_AUTH_KEY is set in environment.")
  else
    vim.health.warn("DEEPL_AUTH_KEY is not set. DeepL engine needs setup({ api_key = '...' }) or env key.")
  end

  if has_env_key("GOOGLE_TRANSLATE_API_KEY") or has_env_key("GOOGLE_API_KEY") then
    vim.health.ok("Google API key is set in environment.")
  else
    vim.health.warn("GOOGLE_TRANSLATE_API_KEY/GOOGLE_API_KEY is not set. Google engine requires an API key.")
  end
end

return M
