local M = {}

local async_case = require("tests.headless.helpers.async_case")
local mock = require("tests.headless.helpers.mock_system")
local provider_common = require("translate.providers.common")

function M.run()
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
end

return M
