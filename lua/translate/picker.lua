local M = {}

function M.open(items, opts)
  vim.schedule(function()
    vim.ui.select(items, {
      prompt = opts.prompt,
      format_item = opts.format_item,
    }, function(choice)
      if choice and type(opts.on_choice) == "function" then
        opts.on_choice(choice)
      end
    end)
  end)
end

function M.target_formatter(current_target)
  return function(item)
    if item.code == current_target then
      return ("%s (%s) [current]"):format(item.name, item.code)
    end

    return ("%s (%s)"):format(item.name, item.code)
  end
end

function M.engine_formatter(current_engine, resolve_label)
  return function(engine)
    local label = resolve_label(engine)
    if engine == current_engine then
      return ("%s (%s) [current]"):format(label, engine)
    end

    return ("%s (%s)"):format(label, engine)
  end
end

return M
