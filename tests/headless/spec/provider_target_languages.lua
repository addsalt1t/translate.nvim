local M = {}

local async_case = require("tests.headless.helpers.async_case")
local mock = require("tests.headless.helpers.mock_system")
local deepl = require("translate.deepl")
local google = require("translate.google")

function M.run()
  mock.with_mock_system({
    {
      code = 0,
      stdout = [[
        [
          {"language":"JA","name":"Japanese"},
          {"language":"EN-US","name":"English (American)"}
        ]
      ]],
      stderr = "",
    },
  }, function(calls, records)
    local err_msg, languages = async_case.await_callback("deepl target languages", 1000, function(done)
      deepl.target_languages({
        api_key = "dummy",
        free_api = true,
      }, function(err, items)
        done(err, items)
      end)
    end)

    assert(err_msg == nil, ("deepl target_languages failed: %s"):format(tostring(err_msg)))
    assert(type(languages) == "table" and #languages == 2, "deepl target_languages should return two items")
    assert(languages[1].code == "EN-US", "deepl target_languages should sort by name")
    assert(languages[2].code == "JA", "deepl target_languages should keep remaining languages")
    assert(mock.has_arg(calls[1], "--config"), "deepl target_languages should pass auth header through curl config stdin")
    assert(type(records[1].opts.stdin) == "string", "deepl target_languages should provide curl config stdin")
    assert(string.find(records[1].opts.stdin, "DeepL-Auth-Key dummy", 1, true), "deepl auth header missing from stdin")
  end)

  mock.with_mock_system({
    {
      code = 0,
      stdout = "[]",
      stderr = "",
    },
  }, function()
    local err_msg = async_case.await_callback("deepl target languages empty", 1000, function(done)
      deepl.target_languages({
        api_key = "dummy",
        free_api = true,
      }, function(err)
        done(err)
      end)
    end)

    assert(err_msg == "DeepL returned no target languages.", "deepl empty language response should raise a clear error")
  end)

  mock.with_mock_system({
    {
      code = 0,
      stdout = [[
        {
          "data": {
            "languages": [
              {"language":"zh-Hans","name":"Chinese (Simplified)"},
              {"language":"EN-US","name":"English"},
              {"language":"en","name":"English Duplicate"},
              {"language":"ko","name":"Korean"}
            ]
          }
        }
      ]],
      stderr = "",
    },
  }, function(calls, records)
    local err_msg, languages = async_case.await_callback("google target languages", 1000, function(done)
      google.target_languages({
        google_api_key = "dummy",
      }, function(err, items)
        done(err, items)
      end)
    end)

    assert(err_msg == nil, ("google target_languages failed: %s"):format(tostring(err_msg)))
    assert(type(languages) == "table" and #languages == 3, "google target_languages should dedupe normalized language codes")
    assert(languages[1].code == "ZH-CN", "google target_languages should normalize zh-Hans to ZH-CN")
    assert(languages[2].code == "EN", "google target_languages should normalize EN-US/en to EN")
    assert(languages[3].code == "KO", "google target_languages should preserve other languages")
    assert(mock.has_arg(calls[1], "--config"), "google target_languages should pass api key through curl config stdin")
    assert(type(records[1].opts.stdin) == "string", "google target_languages should provide curl config stdin")
    assert(string.find(records[1].opts.stdin, "X-Goog-Api-Key: dummy", 1, true), "google api key header missing from stdin")
  end)

  mock.with_mock_system({
    {
      code = 0,
      stdout = [[{"data":{}}]],
      stderr = "",
    },
  }, function()
    local err_msg = async_case.await_callback("google target languages malformed", 1000, function(done)
      google.target_languages({
        google_api_key = "dummy",
      }, function(err)
        done(err)
      end)
    end)

    assert(err_msg == "Google Cloud response has no languages.", "google malformed language response should surface a clear error")
  end)
end

return M
