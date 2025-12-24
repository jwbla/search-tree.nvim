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
  local ui = require("search-tree.ui")
  
  -- Initialize UI for streaming
  if not ui.init_tree_for_streaming(term, config) then
    return
  end
  
  -- Execute streaming search
  search.search_async_stream(
    term,
    config.ripgrep or {},
    -- on_result: called for each match as it arrives
    function(match)
      ui.add_match(match)
    end,
    -- on_complete: called when search finishes
    function(err, result_count)
      ui.search_complete(err, result_count)
    end
  )
end

return M

