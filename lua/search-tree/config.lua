local M = {}

local defaults = {
  keymap = false,
  rainbow_tree = false,
  keymaps = {
    next_pane = "<Tab>",
    prev_pane = "<S-Tab>",
  },
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
    include_patterns = {}, -- Glob patterns to include: {"*.lua", "*.py"} (whitelist)
  },
}

M.options = vim.deepcopy(defaults)

local function validate(cfg)
  vim.validate({
    ["window.position"] = { cfg.window.position, function(v)
      return v == "float" or v == "split"
    end, "'float' or 'split'" },
    ["window.width"] = { cfg.window.width, function(v)
      return type(v) == "number" and v > 0 and v <= 1
    end, "number between 0 and 1" },
    ["window.height"] = { cfg.window.height, function(v)
      return type(v) == "number" and v > 0 and v <= 1
    end, "number between 0 and 1" },
    ["ripgrep.case_sensitive"] = { cfg.ripgrep.case_sensitive, "boolean" },
    ["ripgrep.exclude_patterns"] = { cfg.ripgrep.exclude_patterns, "table" },
    ["ripgrep.include_patterns"] = { cfg.ripgrep.include_patterns, "table" },
    ["keymaps.next_pane"] = { cfg.keymaps.next_pane, "string" },
    ["keymaps.prev_pane"] = { cfg.keymaps.prev_pane, "string" },
  })
end

function M.setup(opts)
  opts = opts or {}
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  validate(M.options)
end

return M
