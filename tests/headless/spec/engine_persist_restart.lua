local M = {}

local function read_json(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  local lines = vim.fn.readfile(path)
  if not lines or #lines == 0 then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok or type(decoded) ~= "table" then
    return nil
  end
  return decoded
end

function M.run()
  local state_path = vim.fs.normalize(vim.fn.stdpath("state") .. "/translate.nvim/test-engine-state.json")
  pcall(vim.fn.delete, state_path)

  local translate = require("translate")
  local opts = {
    persist_target = true,
    state_path = state_path,
    engine = "deepl",
    default_target = "KO",
    api_key = "dummy-deepl",
    google_api_key = "dummy-google",
  }

  translate.setup(opts)
  assert(translate.current_engine() == "deepl", "initial engine should follow setup default")

  translate.set_engine("google")
  assert(translate.current_engine() == "google", "engine switch to google failed")

  local payload = read_json(state_path)
  assert(type(payload) == "table", "state file payload is missing")
  assert(payload.engine == "google", "state file should persist selected engine")

  package.loaded["translate"] = nil
  local restarted = require("translate")
  local restart_opts = vim.tbl_extend("force", {}, opts)
  restart_opts.engine = nil
  restarted.setup(restart_opts)
  assert(restarted.current_engine() == "google", "setup should restore last selected engine from state file")

  pcall(vim.fn.delete, state_path)
end

return M
