local M = {}

local state = {
  buf = nil,
  win = nil,
  input_buf = nil,
  input_win = nil,
  exclude_buf = nil,
  exclude_win = nil,
  include_buf = nil,
  include_win = nil,
  preview_buf = nil,
  preview_win = nil,
  preview_path = nil,
  tree_data = nil,
  expanded_files = {},
  expanded_dirs = {},
  line_map = {},
  search_term = "",
  exclude_text = "",
  include_text = "",
  config = {},
  previous_win = nil,
  updating = false,
  closing = false,
}

local preview_ns = vim.api.nvim_create_namespace("search_tree_preview")

-- Forward declarations
local create_float_layout
local update_preview
local focus_input
local focus_exclude
local focus_include
local focus_results
local execute_search

------------------------------------------------------------------------
-- Close
------------------------------------------------------------------------
function M.close()
  if state.closing then
    return
  end
  state.closing = true

  pcall(vim.api.nvim_del_augroup_by_name, "SearchTree")

  for _, key in ipairs({ "include_win", "exclude_win", "input_win", "preview_win", "win" }) do
    local w = state[key]
    if w and vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim_win_close, w, true)
    end
    state[key] = nil
  end

  for _, key in ipairs({ "include_buf", "exclude_buf", "input_buf", "preview_buf", "buf" }) do
    local b = state[key]
    if b and vim.api.nvim_buf_is_valid(b) then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
    state[key] = nil
  end

  state.tree_data = nil
  state.expanded_files = {}
  state.expanded_dirs = {}
  state.line_map = {}
  state.preview_path = nil
  state.updating = false
  state.closing = false
end

------------------------------------------------------------------------
-- Focus helpers
------------------------------------------------------------------------
focus_input = function()
  if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
    vim.api.nvim_set_current_win(state.input_win)
    vim.cmd("startinsert!")
  end
end

focus_exclude = function()
  if state.exclude_win and vim.api.nvim_win_is_valid(state.exclude_win) then
    vim.api.nvim_set_current_win(state.exclude_win)
    vim.cmd("startinsert!")
  end
end

focus_include = function()
  if state.include_win and vim.api.nvim_win_is_valid(state.include_win) then
    vim.api.nvim_set_current_win(state.include_win)
    vim.cmd("startinsert!")
  end
end

focus_results = function()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.cmd("stopinsert")
    vim.api.nvim_set_current_win(state.win)
  end
end

------------------------------------------------------------------------
-- Exclude patterns
------------------------------------------------------------------------
local function parse_patterns(text)
  if not text or text == "" then
    return {}
  end
  local patterns = {}
  for pattern in text:gmatch("[^,]+") do
    pattern = pattern:match("^%s*(.-)%s*$")
    if pattern ~= "" then
      table.insert(patterns, pattern)
    end
  end
  return patterns
end

------------------------------------------------------------------------
-- Preview
------------------------------------------------------------------------
update_preview = function()
  if state.updating or state.closing then
    return
  end
  if not state.preview_win or not vim.api.nvim_win_is_valid(state.preview_win) then
    return
  end
  if not state.preview_buf or not vim.api.nvim_buf_is_valid(state.preview_buf) then
    return
  end
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    return
  end

  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, state.win)
  if not ok then
    return
  end

  local line_num = cursor[1]
  local line_info = state.line_map[line_num]
  if not line_info or not line_info.path then
    return
  end

  if line_info.type == "directory" then
    return
  end

  state.updating = true

  local file_path = line_info.path
  local match_line = nil

  if line_info.type == "match" then
    match_line = line_info.line
  elseif line_info.type == "file" and line_info.node and line_info.node.matches and #line_info.node.matches > 0 then
    match_line = line_info.node.matches[1].line
  end

  if file_path ~= state.preview_path then
    local read_ok, file_lines = pcall(vim.fn.readfile, file_path)
    if not read_ok or not file_lines then
      state.updating = false
      return
    end

    state.preview_path = file_path

    vim.bo[state.preview_buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.preview_buf, 0, -1, false, file_lines)
    vim.bo[state.preview_buf].modifiable = false

    local ft_ok, ft = pcall(vim.filetype.match, { filename = file_path })
    if ft_ok and ft then
      vim.bo[state.preview_buf].filetype = ft
    else
      vim.bo[state.preview_buf].filetype = ""
    end

    local filename = vim.fn.fnamemodify(file_path, ":t")
    pcall(vim.api.nvim_win_set_config, state.preview_win, {
      title = " " .. filename .. " ",
      title_pos = "center",
    })
  end

  vim.api.nvim_buf_clear_namespace(state.preview_buf, preview_ns, 0, -1)

  if match_line then
    local line_count = vim.api.nvim_buf_line_count(state.preview_buf)
    if match_line <= line_count then
      vim.api.nvim_buf_add_highlight(state.preview_buf, preview_ns, "Visual", match_line - 1, 0, -1)
      pcall(vim.api.nvim_win_set_cursor, state.preview_win, { match_line, 0 })
      pcall(vim.api.nvim_win_call, state.preview_win, function()
        vim.cmd("normal! zz")
      end)
    end
  end

  state.updating = false
end

------------------------------------------------------------------------
-- Keymap setup
------------------------------------------------------------------------
local function setup_input_keymaps()
  local opts = { buffer = state.input_buf, silent = true, noremap = true }
  local keys = state.config.keymaps or {}
  local next_pane = keys.next_pane or "<Tab>"
  local prev_pane = keys.prev_pane or "<S-Tab>"

  for _, mode in ipairs({ "i", "n" }) do
    vim.keymap.set(mode, "<CR>", function()
      local lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, 1, false)
      local query = lines[1]
      if query and query ~= "" then
        execute_search(query)
      end
    end, opts)
  end

  for _, mode in ipairs({ "i", "n" }) do
    vim.keymap.set(mode, "<Esc>", function()
      vim.cmd("stopinsert")
      M.close()
    end, opts)
  end

  for _, mode in ipairs({ "i", "n" }) do
    vim.keymap.set(mode, next_pane, focus_exclude, opts)
    vim.keymap.set(mode, prev_pane, focus_results, opts)
  end
end

local function setup_exclude_keymaps()
  local opts = { buffer = state.exclude_buf, silent = true, noremap = true }
  local keys = state.config.keymaps or {}
  local next_pane = keys.next_pane or "<Tab>"
  local prev_pane = keys.prev_pane or "<S-Tab>"

  for _, mode in ipairs({ "i", "n" }) do
    vim.keymap.set(mode, "<CR>", function()
      local lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, 1, false)
      local query = lines[1]
      if query and query ~= "" then
        execute_search(query)
      end
    end, opts)
  end

  for _, mode in ipairs({ "i", "n" }) do
    vim.keymap.set(mode, "<Esc>", function()
      vim.cmd("stopinsert")
      M.close()
    end, opts)
  end

  for _, mode in ipairs({ "i", "n" }) do
    vim.keymap.set(mode, next_pane, focus_include, opts)
    vim.keymap.set(mode, prev_pane, focus_input, opts)
  end
end

local function setup_include_keymaps()
  local opts = { buffer = state.include_buf, silent = true, noremap = true }
  local keys = state.config.keymaps or {}
  local next_pane = keys.next_pane or "<Tab>"
  local prev_pane = keys.prev_pane or "<S-Tab>"

  for _, mode in ipairs({ "i", "n" }) do
    vim.keymap.set(mode, "<CR>", function()
      local lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, 1, false)
      local query = lines[1]
      if query and query ~= "" then
        execute_search(query)
      end
    end, opts)
  end

  for _, mode in ipairs({ "i", "n" }) do
    vim.keymap.set(mode, "<Esc>", function()
      vim.cmd("stopinsert")
      M.close()
    end, opts)
  end

  for _, mode in ipairs({ "i", "n" }) do
    vim.keymap.set(mode, next_pane, focus_results, opts)
    vim.keymap.set(mode, prev_pane, focus_exclude, opts)
  end
end

local function setup_results_keymaps()
  local opts = { buffer = state.buf, silent = true, noremap = true }
  local keys = state.config.keymaps or {}
  local next_pane = keys.next_pane or "<Tab>"
  local prev_pane = keys.prev_pane or "<S-Tab>"

  vim.keymap.set("n", "<CR>", function() M.jump_to_match() end, opts)
  vim.keymap.set("n", "<Space>", function() M.toggle_expansion() end, opts)
  vim.keymap.set("n", "l", function() M.expand() end, opts)
  vim.keymap.set("n", "<Right>", function() M.expand() end, opts)
  vim.keymap.set("n", "h", function() M.collapse() end, opts)
  vim.keymap.set("n", "<Left>", function() M.collapse() end, opts)
  vim.keymap.set("n", "q", function() M.close() end, opts)
  vim.keymap.set("n", "<Esc>", function() M.close() end, opts)
  vim.keymap.set("n", "o", function() M.jump_to_match() end, opts)
  vim.keymap.set("n", "a", function() M.toggle_all() end, opts)
  vim.keymap.set("n", "r", function()
    if state.search_term and state.search_term ~= "" then
      execute_search(state.search_term)
    end
  end, opts)

  vim.keymap.set("n", next_pane, focus_input, opts)
  vim.keymap.set("n", prev_pane, focus_include, opts)
end

------------------------------------------------------------------------
-- Float layout creation
------------------------------------------------------------------------
create_float_layout = function(config)
  local window_config = config.window or {}
  local columns = vim.o.columns
  local lines = vim.o.lines

  local outer_width = math.floor(columns * (window_config.width or 0.8))
  local outer_height = math.floor(lines * (window_config.height or 0.8))
  local start_row = math.floor((lines - outer_height) / 2)
  local start_col = math.floor((columns - outer_width) / 2)

  local results_width = math.floor((outer_width - 4) / 2)
  local preview_width = outer_width - 4 - results_width
  local pane_height = outer_height - 8
  local input_width = outer_width - 2

  -- Results buffer + window
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].filetype = "search-tree"
  vim.bo[state.buf].modifiable = false

  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor",
    width = results_width,
    height = pane_height,
    row = start_row,
    col = start_col,
    border = "rounded",
    title = " Results ",
    title_pos = "center",
    style = "minimal",
  })
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].wrap = false

  -- Preview buffer + window
  state.preview_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.preview_buf].buftype = "nofile"
  vim.bo[state.preview_buf].modifiable = false

  state.preview_win = vim.api.nvim_open_win(state.preview_buf, false, {
    relative = "editor",
    width = preview_width,
    height = pane_height,
    row = start_row,
    col = start_col + results_width + 2,
    border = "rounded",
    title = " Preview ",
    title_pos = "center",
    style = "minimal",
    focusable = false,
  })
  vim.wo[state.preview_win].number = true
  vim.wo[state.preview_win].relativenumber = false
  vim.wo[state.preview_win].wrap = false

  -- Input buffer + window
  state.input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.input_buf].buftype = "nofile"

  state.input_win = vim.api.nvim_open_win(state.input_buf, false, {
    relative = "editor",
    width = input_width,
    height = 1,
    row = start_row + pane_height + 2,
    col = start_col,
    border = "rounded",
    title = " Search ",
    title_pos = "center",
    style = "minimal",
  })

  -- Exclude + Include buffers + windows (side-by-side)
  local half_left = math.floor((input_width - 2) / 2)
  local half_right = input_width - 2 - half_left

  state.exclude_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.exclude_buf].buftype = "nofile"

  state.exclude_win = vim.api.nvim_open_win(state.exclude_buf, false, {
    relative = "editor",
    width = half_left,
    height = 1,
    row = start_row + pane_height + 5,
    col = start_col,
    border = "rounded",
    title = " Exclude (globs) ",
    title_pos = "center",
    style = "minimal",
  })

  state.include_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.include_buf].buftype = "nofile"

  state.include_win = vim.api.nvim_open_win(state.include_buf, false, {
    relative = "editor",
    width = half_right,
    height = 1,
    row = start_row + pane_height + 5,
    col = start_col + half_left + 2,
    border = "rounded",
    title = " Include (globs) ",
    title_pos = "center",
    style = "minimal",
  })

  -- Pre-fill exclude input
  if state.exclude_text and state.exclude_text ~= "" then
    vim.api.nvim_buf_set_lines(state.exclude_buf, 0, -1, false, { state.exclude_text })
  end

  -- Pre-fill include input
  if state.include_text and state.include_text ~= "" then
    vim.api.nvim_buf_set_lines(state.include_buf, 0, -1, false, { state.include_text })
  end

  -- Keymaps
  setup_results_keymaps()
  setup_input_keymaps()
  setup_exclude_keymaps()
  setup_include_keymaps()

  -- Autocmds
  local augroup = vim.api.nvim_create_augroup("SearchTree", { clear = true })

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    buffer = state.buf,
    callback = function()
      update_preview()
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    callback = function(args)
      local closed_win = tonumber(args.match)
      if closed_win == state.win or closed_win == state.preview_win or closed_win == state.input_win or closed_win == state.exclude_win or closed_win == state.include_win then
        vim.schedule(function()
          M.close()
        end)
      end
    end,
  })
end

------------------------------------------------------------------------
-- Display a message in the results buffer
------------------------------------------------------------------------
local function set_results_message(msg)
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { "", "  " .. msg })
    vim.bo[state.buf].modifiable = false
  end
end

------------------------------------------------------------------------
-- Execute search
------------------------------------------------------------------------
execute_search = function(query)
  if not query or query == "" then
    return
  end

  local search = require("search-tree.search")
  local tree_mod = require("search-tree.tree")

  vim.cmd("stopinsert")

  -- Read and store exclude text
  if state.exclude_buf and vim.api.nvim_buf_is_valid(state.exclude_buf) then
    local exclude_lines = vim.api.nvim_buf_get_lines(state.exclude_buf, 0, 1, false)
    state.exclude_text = exclude_lines[1] or ""
  end

  -- Read and store include text
  if state.include_buf and vim.api.nvim_buf_is_valid(state.include_buf) then
    local include_lines = vim.api.nvim_buf_get_lines(state.include_buf, 0, 1, false)
    state.include_text = include_lines[1] or ""
  end

  -- Build ripgrep opts — config patterns are already seeded into the UI bars,
  -- so use only the dialog text to avoid double-applying
  local rg_opts = vim.deepcopy(state.config.ripgrep or {})
  rg_opts.exclude_patterns = parse_patterns(state.exclude_text)
  rg_opts.include_patterns = parse_patterns(state.include_text)

  local window_config = state.config.window or {}
  local position = window_config.position or "float"

  -- In split mode, close the floating input, exclude, and include
  if position ~= "float" then
    for _, key in ipairs({ "include", "exclude", "input" }) do
      local win_key = key .. "_win"
      local buf_key = key .. "_buf"
      if state[win_key] and vim.api.nvim_win_is_valid(state[win_key]) then
        pcall(vim.api.nvim_win_close, state[win_key], true)
      end
      if state[buf_key] and vim.api.nvim_buf_is_valid(state[buf_key]) then
        pcall(vim.api.nvim_buf_delete, state[buf_key], { force = true })
      end
      state[win_key] = nil
      state[buf_key] = nil
    end
  end

  -- Reset expansion state for new search
  state.expanded_files = {}
  state.expanded_dirs = {}

  -- Clear stale results immediately
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {})
    vim.bo[state.buf].modifiable = false
  end
  state.line_map = {}
  state.tree_data = nil

  search.search_async(query, rg_opts, function(results, err)
    if err then
      set_results_message("Search error: " .. err)
      return
    end

    if not results or #results == 0 then
      set_results_message("No matches found for: " .. query)
      return
    end

    local tree_structure = tree_mod.build_tree(results)
    local sorted_tree = tree_mod.sort_tree(tree_structure)

    local has_content = false
    if sorted_tree.sorted_dirs and #sorted_tree.sorted_dirs > 0 then
      has_content = true
    elseif sorted_tree.sorted_files and #sorted_tree.sorted_files > 0 then
      has_content = true
    end

    if not has_content then
      set_results_message("No matches found for: " .. query)
      return
    end

    M.show_tree(sorted_tree, query, state.config)
  end)
end

------------------------------------------------------------------------
-- Open input UI
------------------------------------------------------------------------
function M.open_input(config)
  M.close()

  state.config = config
  state.expanded_files = {}
  state.expanded_dirs = {}
  state.line_map = {}
  state.previous_win = vim.api.nvim_get_current_win()

  -- Seed filter bars from config patterns
  local rg = config.ripgrep or {}
  if rg.exclude_patterns and #rg.exclude_patterns > 0 then
    state.exclude_text = table.concat(rg.exclude_patterns, ", ")
  end
  if rg.include_patterns and #rg.include_patterns > 0 then
    state.include_text = table.concat(rg.include_patterns, ", ")
  end

  local window_config = config.window or {}
  local position = window_config.position or "float"

  if position == "float" then
    create_float_layout(config)
    focus_input()
  else
    -- Split mode: simple floating input (original behavior)
    state.input_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.input_buf].buftype = "nofile"

    local win_width = math.floor(vim.o.columns * (window_config.width or 0.8))
    local total_height = math.floor(vim.o.lines * (window_config.height or 0.8))
    local row = math.floor((vim.o.lines - total_height) / 2)
    local col = math.floor((vim.o.columns - win_width) / 2)

    state.input_win = vim.api.nvim_open_win(state.input_buf, true, {
      relative = "editor",
      width = win_width,
      height = 1,
      row = row,
      col = col,
      border = "rounded",
      title = " Search ",
      title_pos = "center",
      style = "minimal",
    })

    -- Exclude + Include buffers + windows (side-by-side, split mode)
    local split_half_left = math.floor((win_width - 2) / 2)
    local split_half_right = win_width - 2 - split_half_left

    state.exclude_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.exclude_buf].buftype = "nofile"

    state.exclude_win = vim.api.nvim_open_win(state.exclude_buf, false, {
      relative = "editor",
      width = split_half_left,
      height = 1,
      row = row + 3,
      col = col,
      border = "rounded",
      title = " Exclude (globs) ",
      title_pos = "center",
      style = "minimal",
    })

    state.include_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.include_buf].buftype = "nofile"

    state.include_win = vim.api.nvim_open_win(state.include_buf, false, {
      relative = "editor",
      width = split_half_right,
      height = 1,
      row = row + 3,
      col = col + split_half_left + 2,
      border = "rounded",
      title = " Include (globs) ",
      title_pos = "center",
      style = "minimal",
    })

    -- Pre-fill exclude input
    if state.exclude_text and state.exclude_text ~= "" then
      vim.api.nvim_buf_set_lines(state.exclude_buf, 0, -1, false, { state.exclude_text })
    end

    -- Pre-fill include input
    if state.include_text and state.include_text ~= "" then
      vim.api.nvim_buf_set_lines(state.include_buf, 0, -1, false, { state.include_text })
    end

    -- Keymaps (split mode uses same configurable keys)
    local keys = state.config.keymaps or {}
    local next_pane = keys.next_pane or "<Tab>"
    local prev_pane = keys.prev_pane or "<S-Tab>"

    -- Search input keymaps
    local input_opts = { buffer = state.input_buf, silent = true, noremap = true }

    vim.keymap.set("i", "<CR>", function()
      local lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, 1, false)
      local q = lines[1]
      if q and q ~= "" then
        execute_search(q)
      end
    end, input_opts)

    vim.keymap.set("i", "<Esc>", function()
      vim.cmd("stopinsert")
      M.close()
    end, input_opts)

    vim.keymap.set("n", "<Esc>", function()
      M.close()
    end, input_opts)

    vim.keymap.set("i", next_pane, focus_exclude, input_opts)
    vim.keymap.set("i", prev_pane, focus_results, input_opts)

    -- Exclude input keymaps
    local exclude_opts = { buffer = state.exclude_buf, silent = true, noremap = true }

    vim.keymap.set("i", "<CR>", function()
      local lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, 1, false)
      local q = lines[1]
      if q and q ~= "" then
        execute_search(q)
      end
    end, exclude_opts)

    vim.keymap.set("i", "<Esc>", function()
      vim.cmd("stopinsert")
      M.close()
    end, exclude_opts)

    vim.keymap.set("n", "<Esc>", function()
      M.close()
    end, exclude_opts)

    vim.keymap.set("i", next_pane, focus_include, exclude_opts)
    vim.keymap.set("i", prev_pane, focus_input, exclude_opts)

    -- Include input keymaps
    local include_opts = { buffer = state.include_buf, silent = true, noremap = true }

    vim.keymap.set("i", "<CR>", function()
      local lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, 1, false)
      local q = lines[1]
      if q and q ~= "" then
        execute_search(q)
      end
    end, include_opts)

    vim.keymap.set("i", "<Esc>", function()
      vim.cmd("stopinsert")
      M.close()
    end, include_opts)

    vim.keymap.set("n", "<Esc>", function()
      M.close()
    end, include_opts)

    vim.keymap.set("i", next_pane, focus_results, include_opts)
    vim.keymap.set("i", prev_pane, focus_exclude, include_opts)

    vim.cmd("startinsert")
  end
end

------------------------------------------------------------------------
-- Show tree (create/update results view)
------------------------------------------------------------------------
function M.show_tree(tree_data, search_term, config)
  state.tree_data = tree_data
  state.search_term = search_term
  state.config = config

  local window_config = config.window or {}
  local position = window_config.position or "float"

  if position == "float" then
    if not state.win or not vim.api.nvim_win_is_valid(state.win) then
      state.previous_win = vim.api.nvim_get_current_win()
      create_float_layout(config)
    end
  else
    -- Split mode
    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
      state.buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(state.buf, "search-tree")
      vim.bo[state.buf].filetype = "search-tree"
      vim.bo[state.buf].buftype = "nofile"
      vim.bo[state.buf].modifiable = false
      M.setup_keybindings()
    end
    if not state.win or not vim.api.nvim_win_is_valid(state.win) then
      state.previous_win = vim.api.nvim_get_current_win()
      M.create_split_window(window_config)
      if not state.win then
        vim.notify("ERROR: Window was not created!", vim.log.levels.ERROR)
        return
      end
    end
  end

  -- Render tree
  local render = require("search-tree.render")
  local lines, highlights, line_map = render.render_tree(
    tree_data, state.expanded_files, state.expanded_dirs, config
  )
  state.line_map = {}
  for i, info in ipairs(line_map) do
    state.line_map[i] = info
  end

  -- Update results buffer
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

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

  if position == "float" then
    -- Update results title with count
    local total = tree_data.count or 0
    pcall(vim.api.nvim_win_set_config, state.win, {
      title = " Results (" .. total .. ") ",
      title_pos = "center",
    })

    -- Pre-fill input with search term
    if state.input_buf and vim.api.nvim_buf_is_valid(state.input_buf) then
      vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { search_term })
    end

    -- Pre-fill exclude input
    if state.exclude_buf and vim.api.nvim_buf_is_valid(state.exclude_buf) and state.exclude_text and state.exclude_text ~= "" then
      vim.api.nvim_buf_set_lines(state.exclude_buf, 0, -1, false, { state.exclude_text })
    end

    -- Pre-fill include input
    if state.include_buf and vim.api.nvim_buf_is_valid(state.include_buf) and state.include_text and state.include_text ~= "" then
      vim.api.nvim_buf_set_lines(state.include_buf, 0, -1, false, { state.include_text })
    end

    -- Focus results
    focus_results()

    -- Schedule preview update
    vim.schedule(update_preview)
  else
    -- Split mode: set buffer on window + window options
    vim.api.nvim_win_set_buf(state.win, state.buf)
    vim.wo[state.win].number = false
    vim.wo[state.win].relativenumber = false
    vim.wo[state.win].wrap = false
  end
end

------------------------------------------------------------------------
-- Split window creation (unchanged)
------------------------------------------------------------------------
function M.create_split_window(config)
  local split_cmd = config.split_position == "right" and "vsplit" or "split"
  vim.cmd(split_cmd)
  state.win = vim.api.nvim_get_current_win()

  if config.width and config.split_position == "right" then
    local width = math.floor(vim.o.columns * config.width)
    vim.api.nvim_win_set_width(state.win, width)
  elseif config.height and config.split_position ~= "right" then
    local height = math.floor(vim.o.lines * config.height)
    vim.api.nvim_win_set_height(state.win, height)
  end
end

------------------------------------------------------------------------
-- Tree operations
------------------------------------------------------------------------
function M.toggle_expansion()
  local line_num = vim.api.nvim_win_get_cursor(state.win)[1]
  local line_info = state.line_map[line_num]
  if not line_info then
    return
  end

  if line_info.type == "file" then
    state.expanded_files[line_info.path] = not state.expanded_files[line_info.path]
  elseif line_info.type == "directory" then
    local currently_expanded = state.expanded_dirs[line_info.path] ~= false
    state.expanded_dirs[line_info.path] = not currently_expanded
  else
    return
  end

  M.show_tree(state.tree_data, state.search_term, state.config)
  pcall(vim.api.nvim_win_set_cursor, state.win, { line_num, 0 })
end

function M.toggle_file()
  M.toggle_expansion()
end

function M.jump_to_match()
  local line_num = vim.api.nvim_win_get_cursor(state.win)[1]
  local line_info = state.line_map[line_num]
  if not line_info then
    return
  end

  if line_info.type == "match" then
    local window_config = state.config.window or {}
    local position = window_config.position or "float"

    if position == "split" then
      if state.previous_win and vim.api.nvim_win_is_valid(state.previous_win) then
        vim.api.nvim_set_current_win(state.previous_win)
      end
      vim.cmd("edit " .. vim.fn.fnameescape(line_info.path))
      vim.api.nvim_win_set_cursor(0, { line_info.line, line_info.column - 1 })
      vim.cmd("normal! zz")
      if state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_set_current_win(state.win)
      end
    else
      M.close()
      vim.cmd("edit " .. vim.fn.fnameescape(line_info.path))
      vim.api.nvim_win_set_cursor(0, { line_info.line, line_info.column - 1 })
      vim.cmd("normal! zz")
    end
  elseif line_info.type == "file" or line_info.type == "directory" then
    M.toggle_expansion()
  end
end

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

function M.toggle_all()
  if not state.tree_data then
    return
  end

  local any_expanded = false
  local has_entries = false
  for _, expanded in pairs(state.expanded_dirs) do
    has_entries = true
    if expanded then
      any_expanded = true
      break
    end
  end

  -- If table is empty, dirs default to expanded (nil ~= false passes in render)
  if not has_entries then
    any_expanded = true
  end

  if any_expanded then
    collapse_all_dirs(state.tree_data, state.expanded_dirs)
  else
    expand_all_dirs(state.tree_data, state.expanded_dirs)
  end

  M.show_tree(state.tree_data, state.search_term, state.config)
end

function M.expand()
  local line_num = vim.api.nvim_win_get_cursor(state.win)[1]
  local line_info = state.line_map[line_num]
  if not line_info then
    return
  end

  if line_info.type == "file" then
    state.expanded_files[line_info.path] = true
  elseif line_info.type == "directory" then
    state.expanded_dirs[line_info.path] = true
  else
    return
  end

  M.show_tree(state.tree_data, state.search_term, state.config)
  pcall(vim.api.nvim_win_set_cursor, state.win, { line_num, 0 })
end

function M.collapse()
  local line_num = vim.api.nvim_win_get_cursor(state.win)[1]
  local line_info = state.line_map[line_num]
  if not line_info then
    return
  end

  if line_info.type == "match" then
    -- Leaf node: find parent file and collapse it
    for i = line_num - 1, 1, -1 do
      if state.line_map[i].type == "file" and state.line_map[i].path == line_info.path then
        state.expanded_files[line_info.path] = false
        M.show_tree(state.tree_data, state.search_term, state.config)
        pcall(vim.api.nvim_win_set_cursor, state.win, { i, 0 })
        return
      end
    end
  elseif line_info.type == "file" then
    if state.expanded_files[line_info.path] then
      -- Expanded: collapse this file
      state.expanded_files[line_info.path] = false
      M.show_tree(state.tree_data, state.search_term, state.config)
      pcall(vim.api.nvim_win_set_cursor, state.win, { line_num, 0 })
    else
      -- Already collapsed: jump to parent directory and collapse it
      local parent_path = vim.fn.fnamemodify(line_info.path, ":h")
      if parent_path == "." then
        return
      end
      for i = line_num - 1, 1, -1 do
        if state.line_map[i].type == "directory" and state.line_map[i].path == parent_path then
          state.expanded_dirs[parent_path] = false
          M.show_tree(state.tree_data, state.search_term, state.config)
          pcall(vim.api.nvim_win_set_cursor, state.win, { i, 0 })
          return
        end
      end
    end
  elseif line_info.type == "directory" then
    if state.expanded_dirs[line_info.path] ~= false then
      -- Expanded: collapse this directory
      state.expanded_dirs[line_info.path] = false
      M.show_tree(state.tree_data, state.search_term, state.config)
      pcall(vim.api.nvim_win_set_cursor, state.win, { line_num, 0 })
    else
      -- Already collapsed: jump to parent directory and collapse it
      local parent_path = vim.fn.fnamemodify(line_info.path, ":h")
      if parent_path == "." then
        return
      end
      for i = line_num - 1, 1, -1 do
        if state.line_map[i].type == "directory" and state.line_map[i].path == parent_path then
          state.expanded_dirs[parent_path] = false
          M.show_tree(state.tree_data, state.search_term, state.config)
          pcall(vim.api.nvim_win_set_cursor, state.win, { i, 0 })
          return
        end
      end
    end
  end
end

------------------------------------------------------------------------
-- Keybindings for split mode (backward compat)
------------------------------------------------------------------------
function M.setup_keybindings()
  local opts = { buffer = state.buf, silent = true, noremap = true }

  vim.keymap.set("n", "<CR>", function() M.jump_to_match() end, opts)
  vim.keymap.set("n", "<Space>", function() M.toggle_expansion() end, opts)
  vim.keymap.set("n", "l", function() M.expand() end, opts)
  vim.keymap.set("n", "<Right>", function() M.expand() end, opts)
  vim.keymap.set("n", "h", function() M.collapse() end, opts)
  vim.keymap.set("n", "<Left>", function() M.collapse() end, opts)
  vim.keymap.set("n", "q", function() M.close() end, opts)
  vim.keymap.set("n", "<Esc>", function() M.close() end, opts)
  vim.keymap.set("n", "o", function() M.jump_to_match() end, opts)
  vim.keymap.set("n", "a", function() M.toggle_all() end, opts)
  vim.keymap.set("n", "r", function()
    if state.search_term and state.search_term ~= "" then
      execute_search(state.search_term)
    end
  end, opts)
end

return M
