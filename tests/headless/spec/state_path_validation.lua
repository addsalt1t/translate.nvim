local M = {}

function M.run()
  local state = require("translate.state")
  local translate = require("translate")

  local ok, err = state.save("tmp/translate-state.json", { target_lang = "KO" })
  assert(ok == false, "relative state_path must be rejected")
  assert(type(err) == "string" and string.find(err, "absolute path", 1, true), "error should mention absolute path")

  local absolute_path = vim.fs.normalize(vim.fn.stdpath("state") .. "/translate.nvim/test-state.json")
  local abs_ok, abs_err = state.save(absolute_path, { target_lang = "KO" })
  assert(abs_ok == true, ("absolute state_path should be accepted: %s"):format(tostring(abs_err)))

  local setup_ok, setup_err = pcall(translate.setup, {
    persist_target = true,
    state_path = "tmp/translate-state.json",
    api_key = "dummy",
  })
  assert(setup_ok == false, "setup must fail fast when state_path is relative")
  assert(type(setup_err) == "string" and string.find(setup_err, "state_path", 1, true), "setup error should mention state_path")
end

return M
