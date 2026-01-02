local M = {}

local state = {
  buf = nil,
  win = nil,
  tree_data = nil,
  expanded_files = {},
  expanded_dirs = {},
  line_map = {},
  search_term = "",
  config = {},
  previous_win = nil,  -- Track the window that was active before opening tree view
}

-- Create or update the tree view window
function M.show_tree(tree_data, search_term, config)
  state.tree_data = tree_data
  state.search_term = search_term
  state.config = config
  
  -- Create buffer if it doesn't exist
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(state.buf, "search-tree")
    vim.api.nvim_buf_set_option(state.buf, "filetype", "search-tree")
    vim.api.nvim_buf_set_option(state.buf, "buftype", "nofile")
    vim.api.nvim_buf_set_option(state.buf, "modifiable", false)
    
    -- Setup keybindings
    M.setup_keybindings()
  end
  
  -- Render tree
  local render = require("search-tree.render")
  local lines, highlights, line_map = render.render_tree(tree_data, state.expanded_files, state.expanded_dirs)
  state.line_map = {}
  
  -- Convert line_map to 1-indexed table for easier lookup
  for i, info in ipairs(line_map) do
    state.line_map[i] = info
  end
  
  -- Update buffer (make sure it's modifiable)
  vim.api.nvim_buf_set_option(state.buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(state.buf, "modifiable", false)
  
  -- Apply highlights
  render.setup_highlights()
  for _, hl in ipairs(highlights) do
    local hl_group, line_num, start_col, end_col = hl[1], hl[2], hl[3], hl[4]
    if start_col and end_col then
      vim.api.nvim_buf_add_highlight(state.buf, 0, hl_group, line_num - 1, start_col, end_col)
    else
      vim.api.nvim_buf_add_highlight(state.buf, 0, hl_group, line_num - 1, 0, -1)
    end
  end
  
  -- Create or update window
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    -- Save the current window before creating the tree view
    state.previous_win = vim.api.nvim_get_current_win()
    
    local window_config = config.window or {}
    local position = window_config.position or "float"
    
    if position == "float" then
      M.create_float_window(window_config)
    else
      M.create_split_window(window_config)
    end
    
    if not state.win then
      vim.notify("ERROR: Window was not created!", vim.log.levels.ERROR)
      return
    end
  end
  
  -- Set window options
  vim.api.nvim_win_set_buf(state.win, state.buf)
  vim.api.nvim_win_set_option(state.win, "number", false)
  vim.api.nvim_win_set_option(state.win, "relativenumber", false)
  vim.api.nvim_win_set_option(state.win, "wrap", false)
end

-- Create floating window
function M.create_float_window(config)
  local width = math.floor(vim.o.columns * (config.width or 0.8))
  local height = math.floor(vim.o.lines * (config.height or 0.8))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    border = "rounded",
    style = "minimal",
  })
end

-- Create split window
function M.create_split_window(config)
  local split_cmd = config.split_position == "right" and "vsplit" or "split"
  vim.cmd(split_cmd)
  state.win = vim.api.nvim_get_current_win()
  
  -- Set window width/height if specified
  if config.width and config.split_position == "right" then
    local width = math.floor(vim.o.columns * config.width)
    vim.api.nvim_win_set_width(state.win, width)
  elseif config.height and config.split_position ~= "right" then
    local height = math.floor(vim.o.lines * config.height)
    vim.api.nvim_win_set_height(state.win, height)
  end
end

-- Close tree view
function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  state.win = nil
  state.buf = nil
  state.tree_data = nil
  state.expanded_files = {}
  state.expanded_dirs = {}
  state.line_map = {}
end

-- Toggle expansion (file or directory)
function M.toggle_expansion()
  local line_num = vim.api.nvim_win_get_cursor(state.win)[1]
  local line_info = state.line_map[line_num]
  
  if not line_info then
    return
  end
  
  if line_info.type == "file" then
    -- Toggle file expansion
    local file_path = line_info.path
    state.expanded_files[file_path] = not state.expanded_files[file_path]
  elseif line_info.type == "directory" then
    -- Toggle directory expansion
    local dir_path = line_info.path
    state.expanded_dirs[dir_path] = not state.expanded_dirs[dir_path]
  else
    return
  end
  
  -- Re-render
  M.show_tree(state.tree_data, state.search_term, state.config)
  
  -- Restore cursor position
  vim.api.nvim_win_set_cursor(state.win, { line_num, 0 })
end

-- Toggle file expansion (for backward compatibility)
function M.toggle_file()
  M.toggle_expansion()
end

-- Jump to match
function M.jump_to_match()
  local line_num = vim.api.nvim_win_get_cursor(state.win)[1]
  local line_info = state.line_map[line_num]
  
  if not line_info then
    return
  end
  
  if line_info.type == "match" then
    local window_config = state.config.window or {}
    local position = window_config.position or "float"
    
    -- In split mode, open file in previous window and keep tree view open
    -- In float mode, close tree view and open file in current window
    if position == "split" then
      -- Switch to previous window and open file there
      if state.previous_win and vim.api.nvim_win_is_valid(state.previous_win) then
        vim.api.nvim_set_current_win(state.previous_win)
      end
      vim.cmd("edit " .. vim.fn.fnameescape(line_info.path))
      vim.api.nvim_win_set_cursor(0, { line_info.line, line_info.column - 1 })
      vim.cmd("normal! zz") -- Center line
      -- Switch back to tree view window
      if state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_set_current_win(state.win)
      end
    else
      -- Float mode: close tree view and open file
      M.close()
      vim.cmd("edit " .. vim.fn.fnameescape(line_info.path))
      vim.api.nvim_win_set_cursor(0, { line_info.line, line_info.column - 1 })
      vim.cmd("normal! zz") -- Center line
    end
  elseif line_info.type == "file" or line_info.type == "directory" then
    -- Toggle expansion
    M.toggle_expansion()
  end
end

-- Expand all directories recursively
local function expand_all_dirs(node, expanded_dirs)
  if node.path and node.path ~= "." then
    expanded_dirs[node.path] = true
  end
  
  if node.sorted_dirs then
    for _, dir_entry in ipairs(node.sorted_dirs) do
      expand_all_dirs(dir_entry.node, expanded_dirs)
    end
  end
end

-- Collapse all directories recursively
local function collapse_all_dirs(node, expanded_dirs)
  if node.path and node.path ~= "." then
    expanded_dirs[node.path] = false
  end
  
  if node.sorted_dirs then
    for _, dir_entry in ipairs(node.sorted_dirs) do
      collapse_all_dirs(dir_entry.node, expanded_dirs)
    end
  end
end

-- Toggle expand/collapse all
function M.toggle_all()
  if not state.tree_data then
    return
  end
  
  -- Check if any directory is expanded
  local any_expanded = false
  for _, expanded in pairs(state.expanded_dirs) do
    if expanded then
      any_expanded = true
      break
    end
  end
  
  -- If any are expanded, collapse all; otherwise expand all
  if any_expanded then
    collapse_all_dirs(state.tree_data, state.expanded_dirs)
  else
    expand_all_dirs(state.tree_data, state.expanded_dirs)
  end
  
  -- Re-render
  M.show_tree(state.tree_data, state.search_term, state.config)
end

-- Expand current item
function M.expand()
  local line_num = vim.api.nvim_win_get_cursor(state.win)[1]
  local line_info = state.line_map[line_num]
  
  if not line_info then
    return
  end
  
  if line_info.type == "file" then
    local file_path = line_info.path
    state.expanded_files[file_path] = true
  elseif line_info.type == "directory" then
    local dir_path = line_info.path
    state.expanded_dirs[dir_path] = true
  else
    return
  end
  
  -- Re-render
  M.show_tree(state.tree_data, state.search_term, state.config)
  vim.api.nvim_win_set_cursor(state.win, { line_num, 0 })
end

-- Collapse current item
function M.collapse()
  local line_num = vim.api.nvim_win_get_cursor(state.win)[1]
  local line_info = state.line_map[line_num]
  
  if not line_info then
    return
  end
  
  if line_info.type == "file" then
    local file_path = line_info.path
    state.expanded_files[file_path] = false
  elseif line_info.type == "directory" then
    local dir_path = line_info.path
    state.expanded_dirs[dir_path] = false
  else
    return
  end
  
  -- Re-render
  M.show_tree(state.tree_data, state.search_term, state.config)
  vim.api.nvim_win_set_cursor(state.win, { line_num, 0 })
end

-- Setup keybindings
function M.setup_keybindings()
  local opts = { buffer = state.buf, silent = true, noremap = true }
  
  -- Jump to match or toggle expansion
  vim.keymap.set("n", "<CR>", function()
    M.jump_to_match()
  end, opts)
  
  -- Toggle expansion
  vim.keymap.set("n", "<Space>", function()
    M.toggle_expansion()
  end, opts)
  
  -- Expand: l and right arrow
  vim.keymap.set("n", "l", function()
    M.expand()
  end, opts)
  vim.keymap.set("n", "<Right>", function()
    M.expand()
  end, opts)
  
  -- Collapse: h and left arrow
  vim.keymap.set("n", "h", function()
    M.collapse()
  end, opts)
  vim.keymap.set("n", "<Left>", function()
    M.collapse()
  end, opts)
  
  -- Close
  vim.keymap.set("n", "q", function()
    M.close()
  end, opts)
  
  -- Open/jump to match
  vim.keymap.set("n", "o", function()
    M.jump_to_match()
  end, opts)
  
  -- Toggle all
  vim.keymap.set("n", "a", function()
    M.toggle_all()
  end, opts)
  
  -- Refresh/re-run search
  vim.keymap.set("n", "r", function()
    -- Re-run search
    local search = require("search-tree.search")
    local tree = require("search-tree.tree")
    
    search.search_async(state.search_term, state.config.ripgrep or {}, function(results, err)
      if err then
        vim.notify("Search error: " .. err, vim.log.levels.ERROR)
        return
      end
      
      local tree_structure = tree.build_tree(results)
      local sorted_tree = tree.sort_tree(tree_structure)
      M.show_tree(sorted_tree, state.search_term, state.config)
    end)
  end, opts)
end

return M

