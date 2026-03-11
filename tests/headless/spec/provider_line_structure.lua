local M = {}

local async_case = require("tests.headless.helpers.async_case")
local mock = require("tests.headless.helpers.mock_system")
local deepl = require("translate.deepl")
local google = require("translate.google")

function M.run()
  mock.with_mock_system({
    {
      code = 0,
      stdout = '{"translations":[{"text":"DEEPL-1"},{"text":"DEEPL-2"}]}',
      stderr = "",
      on_call = function(record)
        for _, value in ipairs(record.args) do
          if type(value) == "string" and string.sub(value, 1, 1) == "@" then
            M._deepl_body_path = string.sub(value, 2)
            M._deepl_body = table.concat(vim.fn.readfile(M._deepl_body_path), "\n")
          end
        end
      end,
    },
  }, function(calls, records)
    local err_msg, output = async_case.await_callback("deepl line structure translate", 1000, function(done)
      deepl.translate({
        api_key = "dummy",
        free_api = true,
        target_lang = "KO",
      }, "line-1\n\nline-2", function(err, translated)
        done(err, translated)
      end)
    end)

    assert(err_msg == nil, ("deepl translate failed: %s"):format(tostring(err_msg)))
    assert(output == "DEEPL-1\n\nDEEPL-2", "deepl must preserve blank line positions")
    assert(mock.has_arg(calls[1], "--config"), "deepl should pass auth header through curl config stdin")
    assert(not mock.has_arg(calls[1], "DeepL-Auth-Key"), "deepl auth header must not be exposed in argv")
    assert(not mock.has_arg(calls[1], "dummy"), "deepl api key must not be exposed in argv")
    assert(not mock.has_arg(calls[1], "line-1"), "deepl request text must not be exposed in argv")
    assert(type(M._deepl_body_path) == "string" and M._deepl_body_path ~= "", "deepl should write request body to a tempfile")
    assert(type(M._deepl_body) == "string" and string.find(M._deepl_body, "text=line-1", 1, true), "deepl body tempfile should contain encoded text payload")
    assert(vim.fn.filereadable(M._deepl_body_path) == 0, "deepl request body tempfile should be cleaned up")
    assert(type(records[1].opts) == "table" and type(records[1].opts.stdin) == "string", "deepl stdin config missing")
    assert(string.find(records[1].opts.stdin, "DeepL-Auth-Key dummy", 1, true), "deepl stdin key config missing")
  end)
  M._deepl_body_path = nil
  M._deepl_body = nil

  mock.with_mock_system({
    {
      code = 0,
      stdout = '{"data":{"translations":[{"translatedText":"GOOGLE-1"},{"translatedText":"GOOGLE-2"}]}}',
      stderr = "",
      on_call = function(record)
        for _, value in ipairs(record.args) do
          if type(value) == "string" and string.sub(value, 1, 1) == "@" then
            M._google_body_path = string.sub(value, 2)
            M._google_body = table.concat(vim.fn.readfile(M._google_body_path), "\n")
          end
        end
      end,
    },
  }, function(calls, records)
    local err_msg, output = async_case.await_callback("google line structure translate", 1000, function(done)
      google.translate({
        target_lang = "KO",
        google_api_key = "dummy",
      }, "line-1\n\nline-2", function(err, translated)
        done(err, translated)
      end)
    end)

    assert(err_msg == nil, ("google translate failed: %s"):format(tostring(err_msg)))
    assert(output == "GOOGLE-1\n\nGOOGLE-2", "google must preserve blank line positions")
    assert(mock.has_arg(calls[1], "--config"), "google cloud should pass api key header through curl config stdin")
    assert(not mock.has_arg(calls[1], "X-Goog-Api-Key"), "google cloud key header must not be exposed in argv")
    assert(not mock.has_arg(calls[1], "dummy"), "google api key must not be exposed in argv")
    assert(not mock.has_arg(calls[1], "line-1"), "google request text must not be exposed in argv")
    assert(type(M._google_body_path) == "string" and M._google_body_path ~= "", "google should write request body to a tempfile")
    assert(type(M._google_body) == "string" and string.find(M._google_body, "q=line-1", 1, true), "google body tempfile should contain encoded text payload")
    assert(vim.fn.filereadable(M._google_body_path) == 0, "google request body tempfile should be cleaned up")
    assert(type(records[1].opts) == "table" and type(records[1].opts.stdin) == "string", "google cloud stdin config missing")
    assert(string.find(records[1].opts.stdin, "X-Goog-Api-Key: dummy", 1, true), "google cloud stdin key config missing")
  end)
  M._google_body_path = nil
  M._google_body = nil

  -- DeepL: indented lines must keep their leading whitespace after translation
  mock.with_mock_system({
    {
      code = 0,
      stdout = '{"translations":[{"text":"TRANSLATED-1"},{"text":"TRANSLATED-2"},{"text":"TRANSLATED-3"}]}',
      stderr = "",
    },
  }, function()
    local err_msg, output = async_case.await_callback("deepl indent preservation", 1000, function(done)
      deepl.translate({
        api_key = "dummy",
        free_api = true,
        target_lang = "KO",
      }, "  indented\n    deeper\n\nnormal", function(err, translated)
        done(err, translated)
      end)
    end)

    assert(err_msg == nil, ("deepl indent translate failed: %s"):format(tostring(err_msg)))
    assert(output == "  TRANSLATED-1\n    TRANSLATED-2\n\nTRANSLATED-3", "deepl must preserve leading whitespace (indentation)")
  end)

  -- DeepL: multi-chunk parallel dispatch assembles results in order
  do
    local line_count = 52
    local input_lines = {}
    for i = 1, line_count do
      table.insert(input_lines, "line-" .. i)
    end
    local input_text = table.concat(input_lines, "\n")

    local function build_deepl_response(start, count)
      local items = {}
      for i = start, start + count - 1 do
        table.insert(items, ('{"text":"D%d"}'):format(i))
      end
      return ('{"translations":[%s]}'):format(table.concat(items, ","))
    end

    mock.with_mock_system({
      { code = 0, stdout = build_deepl_response(1, 50), stderr = "" },
      { code = 0, stdout = build_deepl_response(51, 2), stderr = "" },
    }, function(calls)
      local err_msg, output = async_case.await_callback("deepl parallel chunks", 2000, function(done)
        deepl.translate({
          api_key = "dummy",
          free_api = true,
          target_lang = "KO",
        }, input_text, function(err, translated)
          done(err, translated)
        end)
      end)

      assert(err_msg == nil, ("deepl parallel failed: %s"):format(tostring(err_msg)))
      assert(#calls == 2, ("expected 2 curl calls for deepl parallel, got %d"):format(#calls))
      local output_lines = vim.split(output, "\n", { plain = true })
      assert(#output_lines == line_count, ("expected %d output lines, got %d"):format(line_count, #output_lines))
      assert(output_lines[1] == "D1", "first line must be D1")
      assert(output_lines[50] == "D50", "50th line must be D50")
      assert(output_lines[51] == "D51", "51st line must be D51")
      assert(output_lines[52] == "D52", "52nd line must be D52")
    end)
  end

  -- Google official API: multi-chunk parallel dispatch assembles results in order
  do
    local line_count = 52
    local input_lines = {}
    for i = 1, line_count do
      table.insert(input_lines, "line-" .. i)
    end
    local input_text = table.concat(input_lines, "\n")

    local function build_google_response(start, count)
      local items = {}
      for i = start, start + count - 1 do
        table.insert(items, ('{"translatedText":"G%d"}'):format(i))
      end
      return ('{"data":{"translations":[%s]}}'):format(table.concat(items, ","))
    end

    mock.with_mock_system({
      { code = 0, stdout = build_google_response(1, 50), stderr = "" },
      { code = 0, stdout = build_google_response(51, 2), stderr = "" },
    }, function(calls)
      local err_msg, output = async_case.await_callback("google parallel chunks", 2000, function(done)
        google.translate({
          target_lang = "KO",
          google_api_key = "dummy",
        }, input_text, function(err, translated)
          done(err, translated)
        end)
      end)

      assert(err_msg == nil, ("google parallel failed: %s"):format(tostring(err_msg)))
      assert(#calls == 2, ("expected 2 curl calls for google parallel, got %d"):format(#calls))
      local output_lines = vim.split(output, "\n", { plain = true })
      assert(#output_lines == line_count, ("expected %d output lines, got %d"):format(line_count, #output_lines))
      assert(output_lines[1] == "G1", "first line must be G1")
      assert(output_lines[50] == "G50", "50th line must be G50")
      assert(output_lines[51] == "G51", "51st line must be G51")
      assert(output_lines[52] == "G52", "52nd line must be G52")
    end)
  end

  -- DeepL: parallel chunk fail-fast stops on first error
  do
    local line_count = 52
    local input_lines = {}
    for i = 1, line_count do
      table.insert(input_lines, "line-" .. i)
    end
    local input_text = table.concat(input_lines, "\n")

    mock.with_mock_system({
      { code = 0, stdout = '{"translations":[]}', stderr = "" },
      { code = 1, stdout = "", stderr = "API rate limit" },
    }, function()
      local err_msg = async_case.await_callback("deepl parallel error", 2000, function(done)
        deepl.translate({
          api_key = "dummy",
          free_api = true,
          target_lang = "KO",
        }, input_text, function(err, translated)
          done(err, translated)
        end)
      end)

      assert(err_msg ~= nil, "deepl parallel must report error when a chunk fails")
    end)
  end

  -- Google: indented lines must keep their leading whitespace after translation
  mock.with_mock_system({
    {
      code = 0,
      stdout = '{"data":{"translations":[{"translatedText":"TRANSLATED-1"},{"translatedText":"TRANSLATED-2"},{"translatedText":"TRANSLATED-3"}]}}',
      stderr = "",
    },
  }, function()
    local err_msg, output = async_case.await_callback("google indent preservation", 1000, function(done)
      google.translate({
        target_lang = "KO",
        google_api_key = "dummy",
      }, "  indented\n    deeper\n\nnormal", function(err, translated)
        done(err, translated)
      end)
    end)

    assert(err_msg == nil, ("google indent translate failed: %s"):format(tostring(err_msg)))
    assert(output == "  TRANSLATED-1\n    TRANSLATED-2\n\nTRANSLATED-3", "google must preserve leading whitespace (indentation)")
  end)

  -- DeepL: whitespace-only lines must be preserved without sending empty translation items
  do
    local body_snapshot = nil

    mock.with_mock_system({
      {
        code = 0,
        stdout = '{"translations":[{"text":"DEEPL-ONLY-1"},{"text":"DEEPL-ONLY-2"}]}',
        stderr = "",
        on_call = function(record)
          for _, value in ipairs(record.args) do
            if type(value) == "string" and string.sub(value, 1, 1) == "@" then
              body_snapshot = table.concat(vim.fn.readfile(string.sub(value, 2)), "\n")
            end
          end
        end,
      },
    }, function()
      local err_msg, output = async_case.await_callback("deepl whitespace-only line preservation", 1000, function(done)
        deepl.translate({
          api_key = "dummy",
          free_api = true,
          target_lang = "KO",
        }, "alpha\n   \n\t\nbeta", function(err, translated)
          done(err, translated)
        end)
      end)

      assert(err_msg == nil, ("deepl whitespace-only line translate failed: %s"):format(tostring(err_msg)))
      assert(output == "DEEPL-ONLY-1\n   \n\t\nDEEPL-ONLY-2", "deepl must preserve whitespace-only lines")
      assert(type(body_snapshot) == "string", "deepl whitespace-only test should capture request body")
      assert(select(2, string.gsub(body_snapshot, "text=", "")) == 2, "deepl should skip whitespace-only lines in request body")
    end)
  end

  -- Google: whitespace-only lines must be preserved without sending empty translation items
  do
    local body_snapshot = nil

    mock.with_mock_system({
      {
        code = 0,
        stdout = '{"data":{"translations":[{"translatedText":"GOOGLE-ONLY-1"},{"translatedText":"GOOGLE-ONLY-2"}]}}',
        stderr = "",
        on_call = function(record)
          for _, value in ipairs(record.args) do
            if type(value) == "string" and string.sub(value, 1, 1) == "@" then
              body_snapshot = table.concat(vim.fn.readfile(string.sub(value, 2)), "\n")
            end
          end
        end,
      },
    }, function()
      local err_msg, output = async_case.await_callback("google whitespace-only line preservation", 1000, function(done)
        google.translate({
          target_lang = "KO",
          google_api_key = "dummy",
        }, "alpha\n   \n\t\nbeta", function(err, translated)
          done(err, translated)
        end)
      end)

      assert(err_msg == nil, ("google whitespace-only line translate failed: %s"):format(tostring(err_msg)))
      assert(output == "GOOGLE-ONLY-1\n   \n\t\nGOOGLE-ONLY-2", "google must preserve whitespace-only lines")
      assert(type(body_snapshot) == "string", "google whitespace-only test should capture request body")
      assert(select(2, string.gsub(body_snapshot, "q=", "")) == 2, "google should skip whitespace-only lines in request body")
    end)
  end
end

return M
