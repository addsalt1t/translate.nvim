local M = {}

local async_case = require("tests.headless.helpers.async_case")
local mock = require("tests.headless.helpers.mock_system")
local provider_common = require("translate.providers.common")

function M.run()
  do
    local path, err = provider_common.write_temp_file("provider-common-http", "secret=1")
    assert(err == nil, ("write_temp_file should succeed: %s"):format(tostring(err)))
    assert(type(path) == "string" and path ~= "", "write_temp_file should return a path")

    local ok, result = pcall(function()
      assert(vim.fn.getfperm(path) == "rw-------", "write_temp_file should create owner-only temp files")
      local lines = vim.fn.readfile(path, "b")
      assert(#lines == 1 and lines[1] == "secret=1", "write_temp_file should preserve request body content")
    end)

    vim.fn.delete(path)

    if not ok then
      error(result)
    end
  end

  mock.with_mock_system({
    { code = 0, stdout = '{"ok":true}', stderr = "" },
  }, function()
    local err_msg, decoded = async_case.await_callback("provider_common run_curl_json success", 1000, function(done)
      provider_common.run_curl_json({ "curl", "https://example.test" }, {
        empty_stdout_message = "empty",
        decode_error_message = "decode failed",
      }, function(err, value)
        done(err, value)
      end)
    end)
    assert(err_msg == nil, ("provider_common success should not fail: %s"):format(tostring(err_msg)))
    assert(type(decoded) == "table" and decoded.ok == true, "provider_common success decode mismatch")
  end)

  mock.with_mock_system({
    { code = 0, stdout = "", stderr = "" },
  }, function()
    local err_msg = async_case.await_callback("provider_common run_curl_json empty", 1000, function(done)
      provider_common.run_curl_json({ "curl", "https://example.test" }, {
        empty_stdout_message = "empty",
        decode_error_message = "decode failed",
      }, function(err)
        done(err)
      end)
    end)
    assert(err_msg == "empty", ("provider_common empty message mismatch: %s"):format(tostring(err_msg)))
  end)

  mock.with_mock_system({
    { code = 0, stdout = "not-json", stderr = "" },
  }, function()
    local err_msg = async_case.await_callback("provider_common run_curl_json decode", 1000, function(done)
      provider_common.run_curl_json({ "curl", "https://example.test" }, {
        empty_stdout_message = "empty",
        decode_error_message = "decode failed",
      }, function(err)
        done(err)
      end)
    end)
    assert(err_msg == "decode failed", ("provider_common decode message mismatch: %s"):format(tostring(err_msg)))
  end)

  mock.with_mock_system({
    { code = 7, stdout = "", stderr = "boom" },
  }, function()
    local err_msg = async_case.await_callback("provider_common run_curl_json failure", 1000, function(done)
      provider_common.run_curl_json({ "curl", "https://example.test" }, {
        empty_stdout_message = "empty",
        decode_error_message = "decode failed",
      }, function(err)
        done(err)
      end)
    end)
    assert(err_msg == "boom", ("provider_common transport message mismatch: %s"):format(tostring(err_msg)))
  end)

  mock.with_mock_system({
    { code = 0, stdout = '{"ok":true}', stderr = "", delay_ms = 80 },
  }, function(_, records)
    local callback_count = 0
    local controller = provider_common.run_curl_json({ "curl", "https://example.test" }, {
      empty_stdout_message = "empty",
      decode_error_message = "decode failed",
    }, function()
      callback_count = callback_count + 1
    end)

    assert(type(controller) == "table" and type(controller.kill) == "function", "run_curl_json should return a controller with kill()")
    controller:kill(15)

    vim.wait(160, function()
      return false
    end, 20)

    assert(records[1].killed, "run_curl_json controller should kill the underlying vim.system handle")
    assert(callback_count == 0, "run_curl_json should suppress callbacks after cancellation")
  end)

  do
    local body_path = nil
    local body_snapshot = nil

    mock.with_mock_system({
      {
        code = 0,
        stdout = '{"items":["FIRST","SECOND"]}',
        stderr = "",
        on_call = function(record)
          for _, value in ipairs(record.args) do
            if type(value) == "string" and string.sub(value, 1, 1) == "@" then
              body_path = string.sub(value, 2)
              body_snapshot = table.concat(vim.fn.readfile(body_path), "\n")
            end
          end
        end,
      },
    }, function()
      local err_msg, translated = async_case.await_callback("provider_common translate_chunked_json success", 1000, function(done)
        provider_common.translate_chunked_json({
          text = "alpha\n\nbeta",
          max_per_chunk = 50,
          provider_name = "Example",
          body_prefix = "provider-common-translate",
          build_body = function(chunk)
            return table.concat(chunk, "|")
          end,
          build_args = function(path)
            return { "curl", "https://example.test", "@" .. path }
          end,
          decode_response = function(decoded, expected_count)
            if type(decoded.items) ~= "table" then
              return nil, "missing items"
            end

            local items = {}
            for i = 1, expected_count do
              items[i] = decoded.items[i]
            end
            return items
          end,
          on_done = function(err, value)
            done(err, value)
          end,
        })
      end)

      assert(err_msg == nil, ("translate_chunked_json should succeed: %s"):format(tostring(err_msg)))
      assert(translated == "FIRST\n\nSECOND", ("translate_chunked_json merge mismatch: %s"):format(tostring(translated)))
      assert(type(body_snapshot) == "string" and body_snapshot == "alpha|beta", "translate_chunked_json body builder mismatch")
      assert(type(body_path) == "string" and body_path ~= "", "translate_chunked_json should write a tempfile body")
      assert(vim.fn.filereadable(body_path) == 0, "translate_chunked_json should clean up body tempfiles")
    end)
  end

  mock.with_mock_system({
    {
      code = 0,
      stdout = '{"items":["ONLY-ONE"]}',
      stderr = "",
    },
  }, function()
    local err_msg = async_case.await_callback("provider_common translate_chunked_json count mismatch", 1000, function(done)
      provider_common.translate_chunked_json({
        text = "alpha\nbeta",
        max_per_chunk = 50,
        provider_name = "Example",
        body_prefix = "provider-common-mismatch",
        build_body = function(chunk)
          return table.concat(chunk, "|")
        end,
        build_args = function(path)
          return { "curl", "https://example.test", "@" .. path }
        end,
        decode_response = function(decoded)
          return decoded.items
        end,
        on_done = function(err)
          done(err)
        end,
      })
    end)

    assert(err_msg == "Response returned 1 translations for 2 lines.", "translate_chunked_json should validate response counts")
  end)

  mock.with_mock_system({
    {
      code = 0,
      stdout = '{"languages":[{"code":"KO","name":"Korean"}]}',
      stderr = "",
    },
  }, function()
    local err_msg, languages = async_case.await_callback("provider_common fetch_languages success", 1000, function(done)
      provider_common.fetch_languages({ "curl", "https://example.test" }, {
        empty_stdout_message = "empty",
        decode_error_message = "decode failed",
      }, function(decoded)
        if type(decoded.languages) ~= "table" then
          return nil, "missing languages"
        end
        return decoded.languages
      end, function(err, value)
        done(err, value)
      end)
    end)

    assert(err_msg == nil, ("fetch_languages should succeed: %s"):format(tostring(err_msg)))
    assert(type(languages) == "table" and languages[1].code == "KO", "fetch_languages should pass decoded language lists through")
  end)

  mock.with_mock_system({
    {
      code = 0,
      stdout = '{"ok":true}',
      stderr = "",
    },
  }, function()
    local err_msg = async_case.await_callback("provider_common fetch_languages decode error", 1000, function(done)
      provider_common.fetch_languages({ "curl", "https://example.test" }, {
        empty_stdout_message = "empty",
        decode_error_message = "decode failed",
      }, function()
        return nil, "missing languages"
      end, function(err)
        done(err)
      end)
    end)

    assert(err_msg == "missing languages", "fetch_languages should surface decoder errors")
  end)

  do
    local launches = 0
    local killed = 0
    local errors = {}

    provider_common.dispatch_parallel_chunks({ "one", "two", "three" }, 1, function(chunk, start_idx, callback)
      launches = launches + 1
      local child = {
        kill = function()
          killed = killed + 1
        end,
      }

      if start_idx == 1 then
        callback("boom")
      end

      return child
    end, function(err)
      table.insert(errors, err)
    end)

    assert(#errors == 1 and errors[1] == "boom", "dispatch_parallel_chunks should report synchronous chunk failure once")
    assert(launches == 1, ("dispatch_parallel_chunks should stop after first synchronous failure, got %d launches"):format(launches))
    assert(killed == 1, ("dispatch_parallel_chunks should kill the synchronously failed controller, got %d kills"):format(killed))
  end
end

return M
