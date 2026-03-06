local M = {}

function M.run()
  local state = require("translate.state")
  local translate = require("translate")
  local original_notify = vim.notify
  local notifications = {}

  vim.notify = function(message, level, opts)
    table.insert(notifications, {
      message = message,
      level = level,
      opts = opts,
    })
  end

  local ok, err = pcall(function()
    local save_ok, save_err = state.save("tmp/translate-state.json", { target_lang = "KO" })
    assert(save_ok == false, "relative state_path must be rejected")
    assert(type(save_err) == "string" and string.find(save_err, "absolute path", 1, true), "error should mention absolute path")

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

    local malformed_path = vim.fn.tempname()
    vim.fn.writefile({ "not-json" }, malformed_path)

    local loaded = state.load(malformed_path)
    assert(loaded == nil, "state.load should ignore malformed JSON files")
    assert(#notifications > 0, "state.load should warn when JSON decode fails")
    assert(
      string.find(notifications[#notifications].message or "", "failed to decode state file", 1, true),
      "state.load warning should mention decode failure"
    )

    vim.fn.delete(malformed_path)
  end)

  vim.notify = original_notify

  if not ok then
    error(err)
  end
end

return M
