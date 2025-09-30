---@class EasyProjects
---@field switch_to_project fun(project_path: string): nil
---@field pick_project fun(): nil
---@field add_current_project fun(): nil
---@field add_project fun(project_path: string): nil
---@field edit_projects fun(): nil
---@field close_tab fun(): nil
---@field force_close_tab fun(): nil
---@field setup fun(opts?: table): nil
local M = {}

-- Import modules
local utils = require("easy-projects.utils")
local config = require("easy-projects.config")
local state = require("easy-projects.state")
local ui = require("easy-projects.ui")
local projects = require("easy-projects.projects")
local autocmds = require("easy-projects.autocmds")

--- Switch to a project directory and restore its state
---@param project_path string The project path to switch to
function M.switch_to_project(project_path)
	local expanded_path = utils.expand_path(project_path)
	if not utils.is_directory(expanded_path) then
		return
	end

	-- Check if we're already in the target project
	local current_cwd = vim.fn.getcwd()
	if current_cwd == expanded_path then
		-- Already in the target project, just set as loaded and move to top
		autocmds.set_loaded_project(expanded_path)
		projects.move_to_top(project_path)
		return
	end

	-- Schedule the actual switch to happen after picker closes
	vim.schedule(function()
		-- Disable autocmds during project switching to avoid interference
		autocmds.disable_tracking()

		-- Save current project state BEFORE switching (inside disabled autocmds)
		local current_loaded_project = autocmds.get_loaded_project()
		if current_loaded_project then
			state.save(current_loaded_project)
		end

		-- Get list of old project buffers to close later (after picker is closed)
		local old_buffers = state.get_old_buffers()

		-- Switch to new project directory FIRST
		vim.cmd("cd " .. utils.escape_path(expanded_path))

		-- Then restore new project's state
		local files_opened = state.restore(expanded_path)

		-- Move this project to the top of the list (most recently used)
		projects.move_to_top(project_path)

		-- Close old project buffers (still inside disabled autocmds)
		state.close_old_buffers(old_buffers)

		-- Set the new project as loaded
		autocmds.set_loaded_project(expanded_path)

		-- Re-enable autocmds
		autocmds.enable_tracking()

		-- Trigger User event for other plugins to react
		vim.api.nvim_exec_autocmds("User", { pattern = "LazyProjectChanged" })
	end)
end

--- Open project picker
function M.pick_project()
	projects.pick()
end

--- Add current directory as project
function M.add_current_project()
	projects.add_current()
end

--- Add project by path
---@param project_path string The project path to add
function M.add_project(project_path)
	projects.add(project_path)
end

--- Edit projects file directly
function M.edit_projects()
	projects.edit()
end

--- Check if buffer should be protected from closing
---@param buf integer Buffer ID to check
---@return boolean is_protected True if buffer should not be closed
local function is_protected_buffer(buf)
	local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf })
	local filetype = vim.api.nvim_get_option_value("filetype", { buf = buf })
	local bufname = vim.api.nvim_buf_get_name(buf)

	-- Protect special buffer types
	if buftype ~= "" and buftype ~= "nofile" then
		return true
	end

	-- Protect special filetypes
	local protected_filetypes = {
		"help", "qf", "quickfix", "loclist", "terminal",
		"snacks_explorer", "snacks_layout_box", "neo-tree", "nvim-tree",
		"oil", "lazy", "mason", "lspinfo", "checkhealth"
	}
	for _, ft in ipairs(protected_filetypes) do
		if filetype == ft then
			return true
		end
	end

	-- Protect snacks:// and other special buffers by name
	if bufname:match("snacks://") or bufname:match("lazy://") then
		return true
	end

	return false
end

--- Close current buffer/tab if not modified
function M.close_tab()
	local current_buf = vim.api.nvim_get_current_buf()

	-- Protect special buffers
	if is_protected_buffer(current_buf) then
		vim.notify("Cannot close protected buffer (explorer, terminal, etc.)", vim.log.levels.WARN)
		return
	end

	local is_modified = vim.api.nvim_get_option_value("modified", { buf = current_buf })

	if is_modified then
		vim.notify("Buffer is modified! Use :EasyCloseTab! to force close.", vim.log.levels.WARN)
		return
	end

	M._close_buffer_safely(current_buf, false)
end

--- Force close current buffer/tab regardless of modified state
function M.force_close_tab()
	local current_buf = vim.api.nvim_get_current_buf()

	-- Protect special buffers even in force mode
	if is_protected_buffer(current_buf) then
		vim.notify("Cannot close protected buffer (explorer, terminal, etc.)", vim.log.levels.WARN)
		return
	end

	M._close_buffer_safely(current_buf, true)
end

--- Safely close buffer using the same method as bufferline 'x' buttons
---@param target_buf integer Buffer to close
---@param force boolean Whether to force close
function M._close_buffer_safely(target_buf, force)
	-- Use the exact same function as your bufferline 'x' close buttons
	if _G.Snacks and _G.Snacks.bufdelete then
		local opts = { buf = target_buf }
		if force then
			opts.force = true
		end
		local success = pcall(_G.Snacks.bufdelete, opts)
		if not success then
			vim.notify(force and "Failed to force close buffer" or "Failed to close buffer", vim.log.levels.ERROR)
		end
	else
		-- Fallback if Snacks not available
		local close_cmd = force and "bdelete!" or "bdelete"
		local success = pcall(vim.cmd, close_cmd .. " " .. target_buf)
		if not success then
			vim.notify("Failed to close buffer", vim.log.levels.ERROR)
		end
	end
end

--- Move a file from default register to current folder in Snacks explorer
function M.move_file_to_folder()
	-- Check if we're in Snacks explorer
	local current_buf = vim.api.nvim_get_current_buf()
	local filetype = vim.api.nvim_get_option_value("filetype", { buf = current_buf })

	if filetype ~= "snacks_picker_list" then
		vim.notify("Not in Snacks explorer (filetype: " .. (filetype or "nil") .. ")", vim.log.levels.WARN)
		return
	end

	-- Get current item from Snacks picker (which is used for the explorer)
	if not (_G.Snacks and _G.Snacks.picker) then
		vim.notify("Snacks picker not available", vim.log.levels.ERROR)
		return
	end

	local picker = _G.Snacks.picker.get()
	if not picker or not picker[1] or not picker[1].list or not picker[1].list._current then
		vim.notify("Could not get current item from explorer", vim.log.levels.ERROR)
		return
	end

	local current_item = picker[1].list._current
	if not current_item or not current_item.file then
		vim.notify("No item selected", vim.log.levels.WARN)
		return
	end

	-- Check if current item is a folder
	local item_path = current_item.file
	if vim.fn.isdirectory(item_path) == 0 then
		vim.notify("Current selection is not a folder", vim.log.levels.WARN)
		return
	end

	-- Get file path from clipboard register (where EasyYankPath stores it)
	local source_path = vim.fn.getreg('+')
	if not source_path or source_path == "" then
		vim.notify("No path in clipboard register (use EasyYankPath first)", vim.log.levels.WARN)
		return
	end

	-- Trim whitespace
	source_path = source_path:match("^%s*(.-)%s*$")

	-- Get project root
	local project_root = vim.fn.getcwd()

	-- Convert to absolute path
	local source_absolute = project_root .. "/" .. source_path

	-- Check if source file/folder exists
	if vim.fn.filereadable(source_absolute) == 0 and vim.fn.isdirectory(source_absolute) == 0 then
		vim.notify("Source path does not exist: " .. source_path, vim.log.levels.ERROR)
		return
	end

	-- Get destination folder
	local dest_folder = item_path

	-- Check if trying to move a folder into itself or its subdirectory
	if vim.fn.isdirectory(source_absolute) == 1 then
		-- Normalize paths for comparison (remove trailing slashes)
		local source_normalized = source_absolute:gsub("/$", "")
		local dest_normalized = dest_folder:gsub("/$", "")

		-- Check if destination is the source itself
		if source_normalized == dest_normalized then
			vim.notify("Cannot move folder into itself", vim.log.levels.WARN)
			return
		end

		-- Check if destination is a subdirectory of source
		if dest_normalized:sub(1, #source_normalized + 1) == source_normalized .. "/" then
			vim.notify("Cannot move folder into its own subdirectory", vim.log.levels.WARN)
			return
		end
	end

	-- Get filename from source
	local filename = vim.fn.fnamemodify(source_absolute, ":t")
	local dest_path = dest_folder .. "/" .. filename

	-- Check if destination already exists
	if vim.fn.filereadable(dest_path) == 1 or vim.fn.isdirectory(dest_path) == 1 then
		vim.notify("Destination already exists: " .. dest_path, vim.log.levels.ERROR)
		return
	end

	-- Confirmation dialog
	local dest_folder_name = vim.fn.fnamemodify(dest_folder, ":t")
	local prompt = string.format("Move '%s' to '%s'?", source_path, dest_folder_name)

	vim.ui.select({ "Yes", "No" }, {
		prompt = prompt,
		format_item = function(item)
			return item
		end,
	}, function(choice)
		if not choice or choice == "No" then
			vim.notify("Move cancelled", vim.log.levels.INFO)
			return
		end

		-- Move the file/folder
		local success = vim.fn.rename(source_absolute, dest_path)
		if success ~= 0 then
			vim.notify("Failed to move: " .. source_path, vim.log.levels.ERROR)
			return
		end

		vim.notify("Moved: " .. source_path .. " → " .. dest_folder_name .. "/" .. filename, vim.log.levels.INFO)

		-- Refresh explorer
		local picker_refresh = _G.Snacks.picker.get()
		if picker_refresh and picker_refresh[1] and picker_refresh[1].refresh then
			picker_refresh[1]:refresh()
		end
	end)
end

--- Setup function for configuration
---@param opts? table Optional configuration options
function M.setup(opts)
	opts = opts or {}

	-- Default keymaps (none by default - configure in your Neovim config)
	local default_keymaps = {}

	-- Override default config path if provided
	if opts.config_file then
		-- This would need to be implemented in config module
		-- config.set_projects_config_path(vim.fn.expand(opts.config_file))
	end

	-- Setup keymaps (merge defaults with user provided)
	local keymaps = vim.tbl_extend("force", default_keymaps, opts.keymaps or {})
	for key, action in pairs(keymaps) do
		vim.keymap.set("n", key, function()
			M[action]()
		end, { desc = "Easy Projects: " .. action })
	end

	-- Setup autocmds
	autocmds.setup()
end

return M
