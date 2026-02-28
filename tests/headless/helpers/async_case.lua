local M = {}
local unpack_values = table.unpack or unpack

function M.await_callback(label, timeout_ms, start)
  local done = false
  local values = nil

  start(function(...)
    values = { ... }
    done = true
  end)

  local ok = vim.wait(timeout_ms or 1000, function()
    return done
  end, 20)

  assert(ok, ("%s timeout"):format(label or "async case"))
  return unpack_values(values or {})
end

return M
