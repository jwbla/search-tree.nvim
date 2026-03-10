# Changelog

All notable changes to search-tree.nvim will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Ripgrep-powered async search via `vim.system` (Neovim 0.10+) with `vim.fn.jobstart` fallback
- Hierarchical tree view grouping results by directory, file, and match with counts at each level
- Float mode: four-pane layout with results panel, file preview, search input, and side-by-side exclude/include bars
- Split mode: side-panel results view (left or right) with floating search/exclude/include inputs
- File preview with syntax highlighting and current match line highlighted
- Tree characters (`├─`, `└─`, `│`) with optional rainbow coloring per depth level
- File icons via optional nvim-web-devicons integration
- Expand/collapse for both directory and file nodes
- Toggle all directories expanded/collapsed with `a`
- Bubble-up collapse: pressing `h` on a leaf or already-collapsed node jumps to and collapses the parent
- Re-run current search with `r`
- Tab/S-Tab to cycle focus through Search → Exclude → Include → Results panes
- Configurable pane navigation keys via `keymaps = { next_pane, prev_pane }`
- Include bar for whitelisting file globs (e.g. `*.lua, *.py`) — only matching files are searched
- Exclude bar for blacklisting file globs, side-by-side with Include at 50/50 width
- `ripgrep.include_patterns` config option to pre-apply include globs to all searches
- `:SearchTree [term]` command — opens input prompt when no term is given
- Configurable keymap, window dimensions, split position
- Ripgrep options: case sensitivity, file type filtering, glob exclude/include patterns
- Match text truncated at 100 characters for display
- Extracted config module (`config.lua`) with validation and `vim.tbl_deep_extend` merging
- Health check module (`:checkhealth search-tree`) for Neovim version, ripgrep, devicons, and config validation
- Read-only config proxy on `require("search-tree").config`

### Fixed

- Root-level file connector lines (`│`) now render correctly when the file has siblings below it
- Collapse (`h`/`<Left>`) now works from any node, not just the parent — match nodes collapse their parent file, collapsed files collapse their parent directory
- Ripgrep "No files were searched" error (exit code 2) when glob filters exclude all files is now treated as zero results instead of an error
- Stale results no longer linger in the results pane when a new search returns no matches
- Exclude patterns now use `--glob !<pattern>` instead of `--glob-negate` (correct ripgrep flag)
