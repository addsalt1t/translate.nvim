local M = {}

local function expect_setup_error(opts, pattern)
  local translate = require("translate")
  local ok, err = pcall(translate.setup, opts)
  assert(not ok, "translate.setup should fail for invalid options")
  assert(string.find(tostring(err), pattern, 1, true), ("unexpected setup error: %s"):format(tostring(err)))
end

function M.run()
  package.loaded.translate = nil
  local translate = require("translate")

  expect_setup_error({
    api_key = "dummy",
    persist_target = false,
    keymaps = false,
  }, "keymaps must be a table")

  expect_setup_error({
    api_key = "dummy",
    persist_target = false,
    float = {
      width = "bad",
    },
  }, "float.width must be a positive integer")

  expect_setup_error({
    api_key = "dummy",
    persist_target = false,
    float = {
      height = 0,
    },
  }, "float.height must be a positive integer")

  local notifications = {}
  local original_notify = vim.notify
  vim.notify = function(message, level, opts)
    table.insert(notifications, {
      message = message,
      level = level,
      opts = opts,
    })
  end

  local ok, setup_err = pcall(translate.setup, {
    api_key = "dummy",
    persist_target = false,
    float = {
      max_width_ratio = 0.5,
      max_height_ratio = 0.5,
    },
  })

  vim.wait(500, function()
    return #notifications >= 2
  end, 20)

  vim.notify = original_notify

  assert(ok, ("translate.setup should still accept deprecated ratio keys: %s"):format(tostring(setup_err)))

  local found_width = false
  local found_height = false
  for _, item in ipairs(notifications) do
    if type(item.message) == "string" and string.find(item.message, "max_width_ratio", 1, true) then
      found_width = true
    end
    if type(item.message) == "string" and string.find(item.message, "max_height_ratio", 1, true) then
      found_height = true
    end
  end

  assert(found_width, "translate.setup should warn about deprecated max_width_ratio")
  assert(found_height, "translate.setup should warn about deprecated max_height_ratio")
end

return M
