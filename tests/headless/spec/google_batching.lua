local M = {}

local async_case = require("tests.headless.helpers.async_case")
local mock = require("tests.headless.helpers.mock_system")
local google = require("translate.google")

local function make_cloud_response(start_index, count)
  local items = {}
  for i = 0, count - 1 do
    table.insert(items, ('{"translatedText":"T%d"}'):format(start_index + i))
  end
  return ('{"data":{"translations":[%s]}}'):format(table.concat(items, ","))
end

function M.run()
  local input_lines = {}
  for i = 1, 51 do
    table.insert(input_lines, ("line-%d"):format(i))
  end
  local input = table.concat(input_lines, "\n")
  local body_snapshots = {}

  mock.with_mock_system({
    {
      code = 0,
      stdout = make_cloud_response(1, 50),
      stderr = "",
      on_call = function(record)
        for _, value in ipairs(record.args) do
          if type(value) == "string" and string.sub(value, 1, 1) == "@" then
            table.insert(body_snapshots, table.concat(vim.fn.readfile(string.sub(value, 2)), "\n"))
          end
        end
      end,
    },
    {
      code = 0,
      stdout = make_cloud_response(51, 1),
      stderr = "",
      on_call = function(record)
        for _, value in ipairs(record.args) do
          if type(value) == "string" and string.sub(value, 1, 1) == "@" then
            table.insert(body_snapshots, table.concat(vim.fn.readfile(string.sub(value, 2)), "\n"))
          end
        end
      end,
    },
  }, function(calls)
    local err_msg, output = async_case.await_callback("google batching translate", 1500, function(done)
      google.translate({
        target_lang = "KO",
        google_api_key = "dummy-key",
      }, input, function(err, translated)
        done(err, translated)
      end)
    end)

    assert(err_msg == nil, ("google batching translate error: %s"):format(tostring(err_msg)))
    assert(type(output) == "string" and output ~= "", "google batching output is empty")

    assert(#calls == 2, ("expected 2 batched requests, got %d"):format(#calls))
    assert(#body_snapshots == 2, ("expected 2 request body snapshots, got %d"):format(#body_snapshots))
    assert(select(2, string.gsub(body_snapshots[1], "q=", "")) == 50, "first batch should include 50 q params")
    assert(select(2, string.gsub(body_snapshots[2], "q=", "")) == 1, "second batch should include 1 q param")

    local output_lines = vim.split(output, "\n", { plain = true, trimempty = false })
    assert(#output_lines == 51, ("output line count mismatch: %d"):format(#output_lines))
    assert(output_lines[1] == "T1", "first translated line mismatch")
    assert(output_lines[51] == "T51", "last translated line mismatch")
  end)
end

return M
