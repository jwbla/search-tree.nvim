local M = {}

local RAINBOW_LINKS = {
  "Statement",   -- red-ish
  "Type",        -- yellow/orange-ish
  "String",      -- green-ish
  "Function",    -- cyan/teal-ish
  "Identifier",  -- blue-ish
  "Special",     -- purple/mauve-ish
}

local function rainbow_hl(depth)
  return string.format("SearchTreeRainbow%d", (depth % #RAINBOW_LINKS) + 1)
end

-- Apply tree character highlights (rainbow per-depth or flat)
-- indent_parts: list of {start_byte, end_byte, depth} for each │ in the indent
-- tree_char_start/end: byte range of the ├─/└─ character
-- prefix_end: end of the full tree prefix (used for flat mode)
local function apply_tree_hl(highlights, line_num, prefix_end, indent_parts, tree_char_start, tree_char_end, depth, rainbow)
  if rainbow then
    for _, part in ipairs(indent_parts) do
      table.insert(highlights, { rainbow_hl(part.depth), line_num, part.start_byte, part.end_byte })
    end
    table.insert(highlights, { rainbow_hl(depth), line_num, tree_char_start, tree_char_end })
  else
    table.insert(highlights, { "SearchTreeTree", line_num, 0, prefix_end })
  end
end

-- Check if nvim-web-devicons is available
local function get_icon(filename)
  local ok, devicons = pcall(require, "nvim-web-devicons")
  if ok then
    local icon, hl = devicons.get_icon(filename, nil, { default = true })
    return icon or " ", hl or ""
  end
  return " ", ""
end

local pipe_len = #"│"

-- Recursively render a directory node
local function render_node(node, expanded_dirs, expanded_files, indent_prefix, is_last, lines, highlights, line_map, depth, indent_parts, rainbow)
  indent_prefix = indent_prefix or ""
  depth = depth or 0
  indent_parts = indent_parts or {}
  local tree_char = is_last and "└─" or "├─"

  -- Check if this directory is expanded (default to true - fully expanded by default)
  local is_expanded = expanded_dirs[node.path] ~= false

  -- Render directory name
  local dir_name = node.name == "." and "." or node.name
  local dir_line = string.format("%s%s %s (%d)", indent_prefix, tree_char, dir_name, node.count)
  table.insert(lines, dir_line)

  local tree_char_start = #indent_prefix
  local tree_char_end = tree_char_start + #tree_char
  local dir_name_start = tree_char_end + 1
  apply_tree_hl(highlights, #lines, dir_name_start, indent_parts, tree_char_start, tree_char_end, depth, rainbow)
  table.insert(highlights, { "SearchTreeDirectory", #lines, dir_name_start, -1 })
  table.insert(line_map, { type = "directory", path = node.path, node = node, expanded = is_expanded })

  -- Only render children if expanded
  if not is_expanded then
    return
  end

  local connector = is_last and "  " or "│ "
  local new_indent = indent_prefix .. connector

  -- Build indent parts for children
  local new_indent_parts = {}
  for _, part in ipairs(indent_parts) do
    table.insert(new_indent_parts, part)
  end
  if not is_last then
    table.insert(new_indent_parts, {
      start_byte = #indent_prefix,
      end_byte = #indent_prefix + pipe_len,
      depth = depth,
    })
  end

  -- Render subdirectories
  if node.sorted_dirs then
    for dir_idx, dir_entry in ipairs(node.sorted_dirs) do
      local dir_node = dir_entry.node
      local is_last_dir = dir_idx == #node.sorted_dirs and (not node.sorted_files or #node.sorted_files == 0)
      render_node(dir_node, expanded_dirs, expanded_files, new_indent, is_last_dir, lines, highlights, line_map, depth + 1, new_indent_parts, rainbow)
    end
  end

  -- Render files
  if node.sorted_files then
    for file_idx, file_entry in ipairs(node.sorted_files) do
      local file_node = file_entry.node
      local filename = file_entry.name
      local is_last_file = file_idx == #node.sorted_files

      -- Build full file path for lookup
      local file_path = node.path == "." and filename or (node.path .. "/" .. filename)

      -- Tree characters
      local file_tree_char = is_last_file and "└─" or "├─"

      -- File icon
      local icon, icon_hl = get_icon(filename)

      -- File line
      local file_line = string.format("%s%s %s %s (%d)", new_indent, file_tree_char, icon, filename, file_node.count)
      table.insert(lines, file_line)

      local file_depth = depth + 1
      local file_tree_start = #new_indent
      local file_tree_end = file_tree_start + #file_tree_char
      local tree_end = file_tree_end + 1
      local icon_start = tree_end
      local name_start = icon_start + #icon + 1

      apply_tree_hl(highlights, #lines, tree_end, new_indent_parts, file_tree_start, file_tree_end, file_depth, rainbow)
      table.insert(highlights, { "SearchTreeFile", #lines, name_start, -1 })
      if icon_hl ~= "" then
        table.insert(highlights, { icon_hl, #lines, icon_start, icon_start + #icon })
      end

      -- Use the stored file path
      local actual_file_path = file_node.path or file_path
      local is_file_expanded = expanded_files[actual_file_path] or false

      table.insert(line_map, { type = "file", path = actual_file_path, expanded = is_file_expanded, node = file_node })

      -- Match lines (if expanded)
      if is_file_expanded and file_node.matches then
        local file_connector = is_last_file and "  " or "│ "
        local match_indent = new_indent .. file_connector

        -- Build match indent parts
        local match_indent_parts = {}
        for _, part in ipairs(new_indent_parts) do
          table.insert(match_indent_parts, part)
        end
        if not is_last_file then
          table.insert(match_indent_parts, {
            start_byte = #new_indent,
            end_byte = #new_indent + pipe_len,
            depth = file_depth,
          })
        end

        local match_depth = depth + 2

        for match_idx, match in ipairs(file_node.matches) do
          local is_last_match = match_idx == #file_node.matches
          local match_tree = is_last_match and "└─" or "├─"

          -- Truncate match text if too long
          local match_text = match.text
          if #match_text > 100 then
            match_text = match_text:sub(1, 97) .. "..."
          end

          local match_line = string.format("%s%s %d:%d: %s", match_indent, match_tree, match.line, match.column, match_text)
          table.insert(lines, match_line)

          local match_tree_start = #match_indent
          local match_tree_end = match_tree_start + #match_tree
          local match_content_start = match_tree_end + 1

          apply_tree_hl(highlights, #lines, match_content_start, match_indent_parts, match_tree_start, match_tree_end, match_depth, rainbow)
          table.insert(highlights, { "SearchTreeMatch", #lines, match_content_start, -1 })
          table.insert(line_map, {
            type = "match",
            path = actual_file_path,
            line = match.line,
            column = match.column,
            text = match.text,
          })
        end
      end
    end
  end
end

-- Render tree to buffer lines
function M.render_tree(root_node, expanded_files, expanded_dirs, config)
  expanded_files = expanded_files or {}
  expanded_dirs = expanded_dirs or {}
  config = config or {}
  local rainbow = config.rainbow_tree or false
  local lines = {}
  local highlights = {}
  local line_map = {}

  -- Start rendering from root, but skip root if it's just "."
  if root_node.name == "." and root_node.sorted_dirs then
    -- Render each top-level directory
    for dir_idx, dir_entry in ipairs(root_node.sorted_dirs) do
      local is_last = dir_idx == #root_node.sorted_dirs and (not root_node.sorted_files or #root_node.sorted_files == 0)
      render_node(dir_entry.node, expanded_dirs, expanded_files, "", is_last, lines, highlights, line_map, 0, {}, rainbow)
    end

    -- Also render root-level files if any
    if root_node.sorted_files then
      for file_idx, file_entry in ipairs(root_node.sorted_files) do
        local file_node = file_entry.node
        local filename = file_entry.name
        local is_last_file = file_idx == #root_node.sorted_files

        local file_tree_char = is_last_file and "└─" or "├─"
        local icon, icon_hl = get_icon(filename)
        local actual_file_path = file_node.path or filename
        local is_expanded = expanded_files[actual_file_path] or false

        local file_line = string.format("%s %s %s (%d)", file_tree_char, icon, filename, file_node.count)
        table.insert(lines, file_line)

        local file_tree_end = #file_tree_char
        local tree_end = file_tree_end + 1
        local icon_start = tree_end
        local name_start = icon_start + #icon + 1

        apply_tree_hl(highlights, #lines, tree_end, {}, 0, file_tree_end, 0, rainbow)
        table.insert(highlights, { "SearchTreeFile", #lines, name_start, -1 })
        if icon_hl ~= "" then
          table.insert(highlights, { icon_hl, #lines, icon_start, icon_start + #icon })
        end
        table.insert(line_map, { type = "file", path = actual_file_path, expanded = is_expanded, node = file_node })

        if is_expanded and file_node.matches then
          local file_connector = is_last_file and "  " or "│ "
          local match_indent_parts = {}
          if not is_last_file then
            table.insert(match_indent_parts, {
              start_byte = 0,
              end_byte = pipe_len,
              depth = 0,
            })
          end

          for match_idx, match in ipairs(file_node.matches) do
            local is_last_match = match_idx == #file_node.matches
            local match_tree = is_last_match and "└─" or "├─"
            local match_text = match.text
            if #match_text > 100 then
              match_text = match_text:sub(1, 97) .. "..."
            end
            local match_line = string.format("%s%s %d:%d: %s", file_connector, match_tree, match.line, match.column, match_text)
            table.insert(lines, match_line)

            local match_tree_start = #file_connector
            local match_tree_end = match_tree_start + #match_tree
            local match_content_start = match_tree_end + 1

            apply_tree_hl(highlights, #lines, match_content_start, match_indent_parts, match_tree_start, match_tree_end, 1, rainbow)
            table.insert(highlights, { "SearchTreeMatch", #lines, match_content_start, -1 })
            table.insert(line_map, {
              type = "match",
              path = actual_file_path,
              line = match.line,
              column = match.column,
              text = match.text,
            })
          end
        end
      end
    end
  else
    -- Render root node directly
    render_node(root_node, {}, expanded_files, "", true, lines, highlights, line_map, 0, {}, rainbow)
  end

  return lines, highlights, line_map
end

-- Setup syntax highlighting (links to standard groups so any colorscheme works)
function M.setup_highlights()
  vim.api.nvim_set_hl(0, "SearchTreeTree", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "SearchTreeDirectory", { default = true, link = "Directory" })
  vim.api.nvim_set_hl(0, "SearchTreeFile", { default = true, link = "String" })
  vim.api.nvim_set_hl(0, "SearchTreeMatch", { default = true, link = "Normal" })
  for i, link_group in ipairs(RAINBOW_LINKS) do
    vim.api.nvim_set_hl(0, string.format("SearchTreeRainbow%d", i), { default = true, link = link_group })
  end
  vim.api.nvim_set_hl(0, "SearchTreeHiddenCursor", { blend = 100, nocombine = true })
end

return M
