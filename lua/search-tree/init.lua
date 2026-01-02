local M = {}

local default_config = {
  keymap = "<leader>pt",
  window = {
    position = "float", -- or "split"
    width = 0.8,
    height = 0.8,
    split_position = "right", -- for split mode
  },
  ripgrep = {
    case_sensitive = false,
    file_types = nil, -- nil = all files
    exclude_patterns = {}, -- Glob patterns to exclude: {"**/libs/*", "**/*.tmp", "*.xfi"}
  },
}

local config = vim.deepcopy(default_config)

-- Setup function
function M.setup(opts)
  opts = opts or {}
  config = vim.tbl_deep_extend("force", default_config, opts)
  
  -- Setup keybinding
  if config.keymap then
    vim.keymap.set("n", config.keymap, function()
      M.search()
    end, { desc = "Search Tree" })
  end
  
  -- Create command
  vim.api.nvim_create_user_command("SearchTree", function(opts)
    local term = opts.args
    if term == "" then
      M.search()
    else
      M.search(term)
    end
  end, { nargs = "?", desc = "Search and display results in tree view" })
end

-- Main search function
function M.search(term)
  if not term then
    term = vim.fn.input("Search: ")
  end
  
  if term == "" or term == nil then
    return
  end
  
  local search = require("search-tree.search")
  local tree = require("search-tree.tree")
  local ui = require("search-tree.ui")
  
  -- Execute async search
  search.search_async(term, config.ripgrep or {}, function(results, err)
    if err then
      vim.notify("Search error: " .. err, vim.log.levels.ERROR)
      return
    end
    
    if not results or #results == 0 then
      vim.notify("No matches found for: " .. term, vim.log.levels.INFO)
      return
    end
    
    -- Build tree structure
    local tree_structure = tree.build_tree(results)
    local sorted_tree = tree.sort_tree(tree_structure)
    
    -- Check if tree has any content
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
    
    -- Display tree
    ui.show_tree(sorted_tree, term, config)
  end)
end

return M

