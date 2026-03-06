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
