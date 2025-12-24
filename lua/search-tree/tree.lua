local M = {}

-- Helper function to get or create a node in the tree
local function get_or_create_node(tree, path_parts, is_file)
  local current = tree
  
  for i, part in ipairs(path_parts) do
    local is_last = i == #path_parts
    
    if is_last and is_file then
      -- This is the filename, create file node
      if not current.files then
        current.files = {}
      end
      if not current.files[part] then
        current.files[part] = {
          name = part,
          path = table.concat(path_parts, "/"),
          count = 0,
          matches = {},
        }
      end
      return current.files[part]
    else
      -- This is a directory, create or get directory node
      if not current.dirs then
        current.dirs = {}
      end
      if not current.dirs[part] then
        current.dirs[part] = {
          name = part,
          path = table.concat(path_parts, "/", 1, i),
          count = 0,
          dirs = {},
          files = {},
        }
      end
      current = current.dirs[part]
    end
  end
  
  return current
end

-- Recursively calculate counts for a directory node
local function calculate_counts(node)
  node.count = 0
  
  -- Count files
  if node.files then
    for _, file in pairs(node.files) do
      node.count = node.count + file.count
    end
  end
  
  -- Count subdirectories (recursively)
  if node.dirs then
    for _, dir in pairs(node.dirs) do
      calculate_counts(dir)
      node.count = node.count + dir.count
    end
  end
end

-- Add a single match to an existing tree structure
function M.add_match_to_tree(root, match)
  local file = match.file
  local parts = vim.split(file, "/", { plain = true })
  
  -- Get or create the file node
  local file_node = get_or_create_node(root, parts, true)
  
  -- Add match to file
  table.insert(file_node.matches, match)
  file_node.count = file_node.count + 1
  
  -- Update counts for all parent directories
  local current = root
  for i = 1, #parts - 1 do
    local part = parts[i]
    if current.dirs and current.dirs[part] then
      current = current.dirs[part]
      current.count = current.count + 1
    else
      break
    end
  end
  root.count = root.count + 1
end

-- Build hierarchical tree structure from flat search results
function M.build_tree(results)
  local root = {
    name = ".",
    path = ".",
    count = 0,
    dirs = {},
    files = {},
  }
  
  for _, match in ipairs(results) do
    M.add_match_to_tree(root, match)
  end
  
  return root
end

-- Recursively sort a node's children
local function sort_node(node)
  -- Sort directories
  if node.dirs then
    local sorted_dirs = {}
    for name, dir in pairs(node.dirs) do
      sort_node(dir) -- Recursively sort subdirectories
      table.insert(sorted_dirs, { name = name, node = dir })
    end
    table.sort(sorted_dirs, function(a, b)
      return a.name < b.name
    end)
    node.sorted_dirs = sorted_dirs
  end
  
  -- Sort files
  if node.files then
    local sorted_files = {}
    for name, file in pairs(node.files) do
      table.insert(sorted_files, { name = name, node = file })
    end
    table.sort(sorted_files, function(a, b)
      return a.name < b.name
    end)
    node.sorted_files = sorted_files
  end
end

-- Sort tree structure (can be called incrementally)
function M.sort_tree(root)
  sort_node(root)
  
  -- Return as array format for compatibility with renderer
  -- The root itself is the tree, but we need to handle the case where
  -- root has dirs/files directly
  if root.dirs and #root.sorted_dirs > 0 then
    return root
  elseif root.files and #root.sorted_files > 0 then
    return root
  else
    -- Empty tree
    return root
  end
end


return M

