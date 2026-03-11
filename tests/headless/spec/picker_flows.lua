local M = {}

local function wait_until(label, predicate)
  local ok = vim.wait(1000, predicate, 20)
  assert(ok, ("%s timeout"):format(label))
end

function M.run()
  local translate = require("translate")
  local deepl = require("translate.deepl")
  local google = require("translate.google")
  local original_target_languages = deepl.target_languages
  local original_google_target_languages = google.target_languages
  local original_ui_select = vim.ui.select
  local original_notify = vim.notify

  local picker_calls = {}
  local notifications = {}

  vim.ui.select = function(items, opts, on_choice)
    local rendered = {}
    for _, item in ipairs(items) do
      table.insert(rendered, opts.format_item(item))
    end

    table.insert(picker_calls, {
      prompt = opts.prompt,
      rendered = rendered,
      items = vim.deepcopy(items),
    })

    if opts.prompt == "Select translation engine" then
      on_choice("google")
      return
    end

    if #picker_calls == 1 then
      on_choice(nil)
      return
    end

    on_choice(items[2])
  end

  vim.notify = function(message, level, opts)
    table.insert(notifications, {
      message = message,
      level = level,
      opts = opts,
    })
  end

  local provider_calls = 0
  deepl.target_languages = function(_, on_done)
    provider_calls = provider_calls + 1
    on_done(nil, {
      { code = "KO", name = "Korean" },
      { code = "EN-US", name = "English (American)" },
    })
  end

  local ok, err = pcall(function()
    translate.setup({
      engine = "deepl",
      api_key = "dummy",
      google_api_key = "dummy-google",
      persist_target = false,
      target_lang = "KO",
    })

    translate.select_target()
    wait_until("target picker", function()
      return #picker_calls == 1
    end)

    assert(provider_calls == 1, "target picker should fetch languages the first time")
    assert(picker_calls[1].prompt == "Select DeepL target language", "target picker prompt mismatch")
    assert(
      picker_calls[1].rendered[1] == "Korean (KO) [current]",
      ("current target formatting mismatch: %s"):format(tostring(picker_calls[1].rendered[1]))
    )
    assert(
      picker_calls[1].rendered[2] == "English (American) (EN-US)",
      ("non-current target formatting mismatch: %s"):format(tostring(picker_calls[1].rendered[2]))
    )

    translate.select_target()
    wait_until("cached target picker", function()
      return #picker_calls == 2
    end)

    assert(provider_calls == 1, "target picker should reuse cached languages")
    assert(translate.current_target() == "EN-US", "select_target should update current target from picker choice")

    translate.select_engine()
    wait_until("engine picker", function()
      return #picker_calls == 3
    end)

    assert(picker_calls[3].prompt == "Select translation engine", "engine picker prompt mismatch")
    assert(
      picker_calls[3].rendered[1] == "DeepL (deepl) [current]",
      ("current engine formatting mismatch: %s"):format(tostring(picker_calls[3].rendered[1]))
    )
    assert(
      picker_calls[3].rendered[2] == "Google (google)",
      ("non-current engine formatting mismatch: %s"):format(tostring(picker_calls[3].rendered[2]))
    )
    assert(translate.current_engine() == "google", "select_engine should update current engine from picker choice")

    deepl.target_languages = function(_, on_done)
      provider_calls = provider_calls + 1
      on_done("provider boom")
    end
    translate.setup({
      engine = "deepl",
      api_key = "dummy",
      google_api_key = "dummy-google",
      persist_target = false,
      target_lang = "KO",
    })

    notifications = {}
    local picker_count_before_error = #picker_calls
    translate.select_target()
    wait_until("target picker error notification", function()
      return #notifications > 0
    end)

    assert(#picker_calls == picker_count_before_error, "target picker should not open when provider language lookup fails")
    assert(notifications[#notifications].level == vim.log.levels.ERROR, "target picker failure should notify as error")
    assert(
      notifications[#notifications].message == "provider boom",
      ("target picker failure message mismatch: %s"):format(tostring(notifications[#notifications].message))
    )

    translate.setup({
      engine = "deepl",
      api_key = "dummy",
      google_api_key = "dummy-google",
      persist_target = false,
      target_lang = "KO",
    })

    picker_calls = {}
    provider_calls = 0
    deepl.target_languages = function(_, on_done)
      provider_calls = provider_calls + 1
      vim.defer_fn(function()
        on_done(nil, {
          { code = "KO", name = "Korean" },
          { code = "EN-US", name = "English (American)" },
        })
      end, 60)
    end

    translate.select_target()
    translate.select_target()
    wait_until("deduped target language lookup", function()
      return provider_calls == 1
    end)
    wait_until("deduped target picker", function()
      return #picker_calls == 1
    end)

    assert(provider_calls == 1, "select_target should reuse an in-flight lookup for the same engine")
    assert(#picker_calls == 1, "select_target should only open one picker for an in-flight lookup")

    translate.setup({
      engine = "deepl",
      api_key = "dummy",
      google_api_key = "dummy-google",
      persist_target = false,
      target_lang = "KO",
    })

    picker_calls = {}
    provider_calls = 0
    deepl.target_languages = function(_, on_done)
      provider_calls = provider_calls + 1
      vim.defer_fn(function()
        on_done(nil, {
          { code = "KO", name = "Korean" },
          { code = "EN-US", name = "English (American)" },
        })
      end, 60)
    end
    google.target_languages = function(_, on_done)
      on_done(nil, {
        { code = "KO", name = "Korean" },
      })
    end

    translate.select_target()
    translate.set_engine("google")
    vim.wait(120, function()
      return false
    end, 20)

    assert(provider_calls == 1, "stale target lookup test should issue one provider request")
    assert(#picker_calls == 0, "stale target lookup should not open a picker after switching engines")
  end)

  deepl.target_languages = original_target_languages
  google.target_languages = original_google_target_languages
  vim.ui.select = original_ui_select
  vim.notify = original_notify

  if not ok then
    error(err)
  end
end

return M
