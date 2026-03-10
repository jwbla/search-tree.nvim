local M = {}

-- Compat shim: vim.health.start() requires 0.10+, report_start works on 0.7+
local h = {}
h.start = vim.health.start or vim.health.report_start
h.ok = vim.health.ok or vim.health.report_ok
h.warn = vim.health.warn or vim.health.report_warn
h.error = vim.health.error or vim.health.report_error
h.info = vim.health.info or vim.health.report_info

function M.check()
  h.start("search-tree")

  -- Neovim version
  if vim.fn.has("nvim-0.7") == 1 then
    local v = vim.version()
    h.ok(string.format("Neovim %d.%d.%d", v.major, v.minor, v.patch))
  else
    h.error("Neovim 0.7+ required")
  end

  -- Ripgrep
  if vim.fn.executable("rg") == 1 then
    local ver = vim.fn.system("rg --version"):match("ripgrep (%S+)")
    h.ok("ripgrep found: " .. (ver or "unknown version"))
  else
    h.error("ripgrep (rg) not found in PATH", {
      "Install from https://github.com/BurntSushi/ripgrep",
    })
  end

  -- Optional: nvim-web-devicons
  if pcall(require, "nvim-web-devicons") then
    h.ok("nvim-web-devicons found")
  else
    h.info("nvim-web-devicons not found (optional, for file icons)")
  end

  -- Config validation
  local ok, config = pcall(require, "search-tree.config")
  if ok and config.options then
    h.start("search-tree configuration")
    local cfg = config.options
    local pos = cfg.window.position
    if pos == "float" or pos == "split" then
      h.ok("window.position = '" .. pos .. "'")
    else
      h.warn("window.position = '" .. tostring(pos) .. "' (should be 'float' or 'split')")
    end
    if cfg.keymap then
      h.ok("Global keymap: " .. tostring(cfg.keymap))
    else
      h.info("No global keymap (use :SearchTree or lazy.nvim keys spec)")
    end
    if cfg.ripgrep.include_patterns and #cfg.ripgrep.include_patterns > 0 then
      h.ok("Include patterns: " .. table.concat(cfg.ripgrep.include_patterns, ", "))
    else
      h.info("No include patterns configured (all files searched)")
    end
    if cfg.keymaps then
      h.ok("Pane navigation: next=" .. cfg.keymaps.next_pane .. " prev=" .. cfg.keymaps.prev_pane)
    end
  end
end

return M
