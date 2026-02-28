local M = {}

local SPECS = {
  "tests.headless.spec.config_normalize",
  "tests.headless.spec.ui_size_base_window",
  "tests.headless.spec.engine_switch_target",
  "tests.headless.spec.engine_persist_restart",
  "tests.headless.spec.engine_auto_prefer_google",
  "tests.headless.spec.google_batching",
  "tests.headless.spec.translate_race_guard",
  "tests.headless.spec.commands_keymaps",
  "tests.headless.spec.ui_winhighlight_title",
  "tests.headless.spec.ui_force_wrap",
  "tests.headless.spec.ui_default_top_align",
  "tests.headless.spec.state_path_validation",
  "tests.headless.spec.provider_line_structure",
  "tests.headless.spec.provider_common_http",
  "tests.headless.spec.visual_selection_bounds",
  "tests.headless.spec.health_check",
}

local function ensure_package_path()
  local cwd = vim.fn.getcwd()
  local extra = table.concat({
    cwd .. "/?.lua",
    cwd .. "/?/init.lua",
  }, ";")
  if not string.find(package.path, extra, 1, true) then
    package.path = extra .. ";" .. package.path
  end
end

function M.run()
  ensure_package_path()

  local failures = {}

  for _, module_name in ipairs(SPECS) do
    package.loaded[module_name] = nil
    local ok, spec_or_err = pcall(require, module_name)
    if not ok then
      table.insert(failures, ("%s: load failed: %s"):format(module_name, tostring(spec_or_err)))
    else
      local runner = spec_or_err.run or spec_or_err
      local run_ok, run_err = pcall(runner)
      if not run_ok then
        table.insert(failures, ("%s: %s"):format(module_name, tostring(run_err)))
      end
    end
  end

  if #failures > 0 then
    error("headless test failures:\n- " .. table.concat(failures, "\n- "))
  end

  print(("headless tests passed (%d spec files)"):format(#SPECS))
end

return M
