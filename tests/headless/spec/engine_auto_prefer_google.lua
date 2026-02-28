local M = {}

local function reset_translate_module()
  package.loaded["translate"] = nil
  return require("translate")
end

local function delete_file(path)
  pcall(vim.fn.delete, path)
end

function M.run()
  local state_path = vim.fs.normalize(vim.fn.stdpath("state") .. "/translate.nvim/test-engine-auto-state.json")
  delete_file(state_path)

  local base_opts = {
    persist_target = true,
    state_path = state_path,
    api_key = "dummy-deepl",
    google_api_key = "dummy-google",
    default_target = "KO",
  }

  local translate = reset_translate_module()
  translate.setup(base_opts)
  assert(
    translate.current_engine() == "google",
    "when both keys exist and no saved/explicit engine, initial engine should prefer google"
  )

  translate.set_engine("deepl")
  assert(translate.current_engine() == "deepl", "engine switch to deepl should work")

  local restarted = reset_translate_module()
  restarted.setup(base_opts)
  assert(restarted.current_engine() == "deepl", "saved engine should take precedence after user switch")

  local explicit = reset_translate_module()
  explicit.setup(vim.tbl_extend("force", {}, base_opts, {
    engine = "google",
  }))
  assert(explicit.current_engine() == "google", "explicit engine option should override saved engine")

  delete_file(state_path)
end

return M
