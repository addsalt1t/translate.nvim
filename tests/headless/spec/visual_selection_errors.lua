local M = {}

local function with_fn_overrides(overrides, fn)
  local originals = {}
  for name, replacement in pairs(overrides) do
    originals[name] = vim.fn[name]
    vim.fn[name] = replacement
  end

  local ok, err = pcall(fn)

  for name, original in pairs(originals) do
    vim.fn[name] = original
  end

  if not ok then
    error(err)
  end
end

local function latest_message(notifications)
  local last = notifications[#notifications]
  return last and last.message or nil
end

local function wait_for_notification(notifications, label)
  local ok = vim.wait(1000, function()
    return #notifications > 0
  end, 20)
  assert(ok, ("%s notification timeout"):format(label))
end

function M.run()
  local translate = require("translate")
  local deepl = require("translate.deepl")
  local original_translate = deepl.translate
  local original_notify = vim.notify
  local notifications = {}
  local translate_calls = 0

  vim.notify = function(message, level, opts)
    table.insert(notifications, {
      message = message,
      level = level,
      opts = opts,
    })
  end

  deepl.translate = function(_, _, on_done)
    translate_calls = translate_calls + 1
    on_done(nil, "unexpected")
  end

  local ok, err = pcall(function()
    vim.cmd("enew")
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

    notifications = {}
    with_fn_overrides({
      mode = function()
        return "v"
      end,
      getpos = function()
        return 0
      end,
    }, function()
      translate.translate_visual()
    end)
    wait_for_notification(notifications, "missing selection")
    assert(latest_message(notifications) == "No visual selection found. Please select text in visual mode and try again.", "missing selection message mismatch")

    notifications = {}
    with_fn_overrides({
      mode = function()
        return "\22"
      end,
      getpos = function(mark)
        if mark == "v" then
          return { 0, 1, 1, 0 }
        end
        return { 0, 1, 3, 0 }
      end,
    }, function()
      translate.translate_visual()
    end)
    wait_for_notification(notifications, "blockwise selection")
    assert(latest_message(notifications) == "Blockwise visual mode is not supported. Use charwise (v) or linewise (V).", "blockwise selection message mismatch")

    notifications = {}
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
    with_fn_overrides({
      mode = function()
        return "v"
      end,
      getpos = function()
        return { 0, 1, 1, 0 }
      end,
    }, function()
      translate.translate_visual()
    end)
    wait_for_notification(notifications, "empty selection")
    assert(latest_message(notifications) == "No text selected. Select text in visual mode and try again.", "empty selection message mismatch")

    assert(translate_calls == 0, "translate_visual should not dispatch provider requests for invalid selections")
  end)

  deepl.translate = original_translate
  vim.notify = original_notify

  if not ok then
    error(err)
  end
end

return M
