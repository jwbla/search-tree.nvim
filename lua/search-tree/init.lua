local M = {}

local config = require("search-tree.config")

-- Read-only proxy to config.options
M.config = setmetatable({}, {
  __index = function(_, key)
    return config.options[key]
  end,
  __newindex = function()
    error("use setup() to change configuration")
  end,
})

-- Setup function
function M.setup(opts)
  config.setup(opts)

  -- Setup keybinding (only if user explicitly sets one)
  if config.options.keymap then
    vim.keymap.set("n", config.options.keymap, function()
      M.search()
    end, { desc = "Search Tree" })
  end

  -- Create command
  vim.api.nvim_create_user_command("SearchTree", function(cmd_opts)
    local term = cmd_opts.args
    if term == "" then
      M.search()
    else
      M.search(term)
    end
  end, { nargs = "?", desc = "Search and display results in tree view" })
end

-- Main search function
function M.search(term)
  local ui = require("search-tree.ui")

  -- No term provided: open the input UI
  if not term then
    ui.open_input(config.options)
    return
  end

  if term == "" then
    return
  end

  local search = require("search-tree.search")
  local tree = require("search-tree.tree")

  -- Direct search with provided term
  search.search_async(term, config.options.ripgrep or {}, function(results, err)
    if err then
      vim.notify("Search error: " .. err, vim.log.levels.ERROR)
      return
    end

    if not results or #results == 0 then
      vim.notify("No matches found for: " .. term, vim.log.levels.INFO)
      return
    end

    local tree_structure = tree.build_tree(results)
    local sorted_tree = tree.sort_tree(tree_structure)

    local has_content = false
    if sorted_tree.sorted_dirs and #sorted_tree.sorted_dirs > 0 then
      has_content = true
    elseif sorted_tree.sorted_files and #sorted_tree.sorted_files > 0 then
      has_content = true
    end

    if not has_content then
      vim.notify("No matches found for: " .. term, vim.log.levels.INFO)
      return
    end

    ui.show_tree(sorted_tree, term, config.options)
  end)
end

return M
