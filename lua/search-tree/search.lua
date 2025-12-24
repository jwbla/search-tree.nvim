local M = {}

-- Execute ripgrep and parse results
function M.search(term, opts)
  opts = opts or {}
  local cwd = opts.cwd or vim.fn.getcwd()
  
  -- Build ripgrep command
  local cmd = { "rg", "--vimgrep", "--no-heading" }
  
  if not opts.case_sensitive then
    table.insert(cmd, "--ignore-case")
  end
  
  if opts.file_types then
    table.insert(cmd, "--type")
    table.insert(cmd, opts.file_types)
  end
  
  table.insert(cmd, vim.fn.shellescape(term))
  
  -- Execute ripgrep
  local output = vim.fn.system(cmd)
  
  if vim.v.shell_error ~= 0 then
    if output == "" then
      return {}, "No matches found"
    else
      return {}, "Error: " .. output
    end
  end
  
  -- Parse output
  local results = {}
  for line in vim.gsplit(output, "\n", { plain = true }) do
    if line ~= "" then
      local match = M.parse_line(line)
      if match then
        table.insert(results, match)
      end
    end
  end
  
  return results, nil
end

-- Parse a single line from ripgrep vimgrep output
-- Format: file:line:column:match text
function M.parse_line(line)
  local file, line_num, col, text = line:match("^([^:]+):(%d+):(%d+):(.+)$")
  
  if not file then
    return nil
  end
  
  -- Normalize file path (remove leading ./ if present, handle absolute paths)
  file = file:gsub("^%.%/", "")
  -- If it's an absolute path, make it relative to cwd for display
  if vim.fn.isdirectory(file) == 0 and vim.fn.filereadable(file) == 1 then
    -- File exists, keep as is (could be relative or absolute)
  end
  
  return {
    file = file,
    line = tonumber(line_num),
    column = tonumber(col),
    text = text:gsub("^%s+", ""):gsub("%s+$", ""), -- trim whitespace
  }
end

-- Convert user glob patterns to ripgrep glob format
local function convert_glob_pattern(pattern)
  -- Convert **/libs/* to libs/** for ripgrep
  -- Convert **/*.ext to **/*.ext (same)
  -- Convert *.ext to *.ext (same)
  -- Handle negation if needed
  
  -- If pattern starts with **/, ripgrep handles it the same way
  -- If pattern is just *.ext, it matches at root level
  -- If pattern is **/*.ext, it matches at any level
  
  -- Ripgrep glob patterns work similarly, but we need to handle:
  -- **/libs/* -> should exclude everything in libs directories
  -- **/*.tmp -> should exclude .tmp files anywhere
  -- *.xfi -> should exclude .xfi files at root
  
  -- For ripgrep, we use --glob-negate with the pattern
  -- **/libs/* becomes **/libs/**
  -- **/*.tmp stays **/*.tmp
  -- *.xfi stays *.xfi
  
  -- Replace /* at end with /** to match everything in that directory
  pattern = pattern:gsub("/%*$", "/**")
  
  return pattern
end

-- Async search using jobstart
function M.search_async(term, opts, callback)
  opts = opts or {}
  local cwd = opts.cwd or vim.fn.getcwd()
  
  -- Build ripgrep command as a string for system() call
  local cmd_parts = { "rg", "--vimgrep", "--no-heading" }
  
  if not opts.case_sensitive then
    table.insert(cmd_parts, "--ignore-case")
  end
  
  if opts.file_types then
    table.insert(cmd_parts, "--type")
    table.insert(cmd_parts, opts.file_types)
  end
  
  -- Add exclude patterns
  if opts.exclude_patterns and #opts.exclude_patterns > 0 then
    for _, pattern in ipairs(opts.exclude_patterns) do
      local rg_pattern = convert_glob_pattern(pattern)
      table.insert(cmd_parts, "--glob-negate")
      table.insert(cmd_parts, rg_pattern)
    end
  end
  
  table.insert(cmd_parts, term)
  
  -- Use vim.system if available (Neovim 0.10+), otherwise fall back to jobstart
  if vim.system then
    vim.system(cmd_parts, {
      cwd = cwd,
      text = true,
    }, function(obj)
      vim.schedule(function()
        if obj.code == 1 then
          -- No matches
          callback({}, nil)
          return
        elseif obj.code ~= 0 then
          callback({}, "ripgrep error: " .. (obj.stderr or "unknown error"))
          return
        end
        
        -- Parse results
        local results = {}
        for line in vim.gsplit(obj.stdout or "", "\n", { plain = true }) do
          if line ~= "" then
            local match = M.parse_line(line)
            if match then
              table.insert(results, match)
            end
          end
        end
        
        callback(results, nil)
      end)
    end)
    return
  end
  
  -- Fallback to jobstart for older Neovim
  local stdout = {}
  local stderr = {}
  local job_completed = false
  
  local job_id = vim.fn.jobstart(cmd_parts, {
    cwd = cwd,
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(stdout, line)
        end
      end
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(stderr, line)
        end
      end
    end,
    on_exit = function(_, exit_code)
      if job_completed then
        return
      end
      job_completed = true
      
      vim.schedule(function()
        if exit_code == 1 then
          callback({}, nil)
        elseif exit_code ~= 0 then
          local error_msg = table.concat(stderr, "\n")
          callback({}, error_msg ~= "" and error_msg or "ripgrep error " .. exit_code)
        else
          local results = {}
          for _, line in ipairs(stdout) do
            local match = M.parse_line(line)
            if match then
              table.insert(results, match)
            end
          end
          callback(results, nil)
        end
      end)
    end,
  })
  
  if job_id <= 0 then
    callback({}, "Failed to start job: " .. job_id)
    return
  end
  
  return job_id
end

-- Streaming async search that calls callback for each result as it arrives
function M.search_async_stream(term, opts, on_result, on_complete)
  opts = opts or {}
  on_result = on_result or function() end
  on_complete = on_complete or function() end
  local cwd = opts.cwd or vim.fn.getcwd()
  
  -- Build ripgrep command
  local cmd_parts = { "rg", "--vimgrep", "--no-heading" }
  
  if not opts.case_sensitive then
    table.insert(cmd_parts, "--ignore-case")
  end
  
  if opts.file_types then
    table.insert(cmd_parts, "--type")
    table.insert(cmd_parts, opts.file_types)
  end
  
  -- Add exclude patterns
  if opts.exclude_patterns and #opts.exclude_patterns > 0 then
    for _, pattern in ipairs(opts.exclude_patterns) do
      local rg_pattern = convert_glob_pattern(pattern)
      table.insert(cmd_parts, "--glob-negate")
      table.insert(cmd_parts, rg_pattern)
    end
  end
  
  table.insert(cmd_parts, term)
  
  -- Use jobstart with unbuffered stdout for streaming
  local stderr = {}
  local job_completed = false
  local result_count = 0
  
  local job_id = vim.fn.jobstart(cmd_parts, {
    cwd = cwd,
    stdout_buffered = false, -- Stream line-by-line
    stderr_buffered = true,
    on_stdout = function(_, data)
      -- Process each line as it arrives
      for _, line in ipairs(data) do
        if line ~= "" then
          local match = M.parse_line(line)
          if match then
            result_count = result_count + 1
            vim.schedule(function()
              on_result(match)
            end)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(stderr, line)
        end
      end
    end,
    on_exit = function(_, exit_code)
      if job_completed then
        return
      end
      job_completed = true
      
      vim.schedule(function()
        if exit_code == 1 then
          -- No matches (exit code 1 is normal for ripgrep when no matches found)
          on_complete(nil, result_count)
        elseif exit_code ~= 0 then
          local error_msg = table.concat(stderr, "\n")
          on_complete(error_msg ~= "" and error_msg or "ripgrep error " .. exit_code, result_count)
        else
          on_complete(nil, result_count)
        end
      end)
    end,
  })
  
  if job_id <= 0 then
    vim.schedule(function()
      on_complete("Failed to start job: " .. job_id, 0)
    end)
    return nil
  end
  
  return job_id
end

return M

