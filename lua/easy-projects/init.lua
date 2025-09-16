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

	-- Disable autocmds during project switching to avoid interference
	autocmds.disable_tracking()

	-- Save current project state BEFORE switching (inside disabled autocmds)
	local current_loaded_project = autocmds.get_loaded_project()
	if current_loaded_project then
		state.save(current_loaded_project)
	end

	-- Get list of old project buffers to close later
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
		if force then
			-- For force close, pass force option to Snacks
			local success = pcall(_G.Snacks.bufdelete, target_buf, { force = true })
			if not success then
				vim.notify("Failed to force close buffer", vim.log.levels.ERROR)
			end
		else
			-- Regular close - let Snacks handle all the navigation and layout logic
			local success = pcall(_G.Snacks.bufdelete, target_buf)
			if not success then
				vim.notify("Failed to close buffer", vim.log.levels.ERROR)
			end
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
