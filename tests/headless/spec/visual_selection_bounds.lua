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

function M.run()
  local translate = require("translate")
  local deepl_provider = require("translate.deepl")

  local original_translate = deepl_provider.translate
  local original_notify = vim.notify
  local captured = {}

  vim.notify = function() end
  deepl_provider.translate = function(_, text, on_done)
    table.insert(captured, text)
    on_done(nil, text)
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

    local buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "abcde", "fghij", "klmno" })

    with_fn_overrides({
      mode = function()
        return "v"
      end,
      getpos = function(mark)
        if mark == "v" then
          return { 0, 1, 5, 0 }
        end
        if mark == "." then
          return { 0, 1, 2, 0 }
        end
        return { 0, 0, 0, 0 }
      end,
    }, function()
      translate.translate_visual()
    end)
    assert(captured[#captured] == "bcde", "mode charwise reverse bounds normalize failed")

    with_fn_overrides({
      mode = function()
        return "V"
      end,
      getpos = function(mark)
        if mark == "v" then
          return { 0, 1, 3, 0 }
        end
        if mark == "." then
          return { 0, 2, 2, 0 }
        end
        return { 0, 0, 0, 0 }
      end,
    }, function()
      translate.translate_visual()
    end)
    assert(captured[#captured] == "abcde\nfghij", "mode linewise bounds normalize failed")

    vim.api.nvim_buf_set_mark(buf, "<", 1, 4, {})
    vim.api.nvim_buf_set_mark(buf, ">", 1, 1, {})
    with_fn_overrides({
      mode = function()
        return "n"
      end,
      visualmode = function()
        return "v"
      end,
    }, function()
      translate.translate_visual()
    end)
    assert(captured[#captured] == "bcde", "marks charwise reverse bounds normalize failed")

    vim.api.nvim_buf_set_mark(buf, "<", 1, 2, {})
    vim.api.nvim_buf_set_mark(buf, ">", 2, 0, {})
    with_fn_overrides({
      mode = function()
        return "n"
      end,
      visualmode = function()
        return "V"
      end,
    }, function()
      translate.translate_visual()
    end)
    assert(captured[#captured] == "abcde\nfghij", "marks linewise bounds normalize failed")
  end)

  deepl_provider.translate = original_translate
  vim.notify = original_notify

  if not ok then
    error(err)
  end
end

return M
