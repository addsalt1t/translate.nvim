local M = {}

local function clone_table(value)
  if type(value) ~= "table" then
    return value
  end
  return vim.deepcopy(value)
end

function M.with_mock_system(queue, fn)
  local original_system = vim.system
  local calls = {}
  local call_records = {}
  local index = 1

  vim.system = function(args, opts, on_done)
    table.insert(calls, clone_table(args))
    local record = {
      args = clone_table(args),
      opts = clone_table(opts),
      killed = false,
      kill_count = 0,
      kill_signal = nil,
    }
    table.insert(call_records, record)

    local response = queue[index]
    index = index + 1
    if not response then
      error(("unexpected vim.system call #%d"):format(index - 1))
    end

    local payload = {
      code = response.code or 0,
      stdout = response.stdout or "",
      stderr = response.stderr or "",
    }

    if type(response.on_call) == "function" then
      response.on_call(record)
    end

    local delay = tonumber(response.delay_ms) or 0
    if delay > 0 then
      vim.defer_fn(function()
        on_done(payload)
      end, delay)
    else
      vim.schedule(function()
        on_done(payload)
      end)
    end

    return {
      kill = function(_, signal)
        record.killed = true
        record.kill_count = record.kill_count + 1
        record.kill_signal = signal
      end,
      wait = function()
        return payload
      end,
    }
  end

  local ok, result = pcall(fn, calls, call_records)
  vim.system = original_system

  if not ok then
    error(result)
  end

  local remaining = #queue - (index - 1)
  if remaining > 0 then
    error(("unused mock responses: %d"):format(remaining))
  end

  return result, calls
end

function M.count_occurrences(args, pattern)
  local count = 0
  for _, value in ipairs(args) do
    if type(value) == "string" and string.find(value, pattern, 1, true) then
      count = count + 1
    end
  end
  return count
end

function M.has_arg(args, pattern)
  return M.count_occurrences(args, pattern) > 0
end

return M
