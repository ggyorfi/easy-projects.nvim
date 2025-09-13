---@class EasyProjects.Autocmds
---@field setup fun(): nil
---@field disable_tracking fun(): nil
---@field enable_tracking fun(): nil
---@field set_loaded_project fun(project_path: string|nil): nil
---@field get_loaded_project fun(): string|nil
local M = {}

local state = require("easy-projects.state")
local config = require("easy-projects.config")
local ui = require("easy-projects.ui")

-- Track if a project is currently loaded (not just in a project directory)
local current_loaded_project = nil

--- Save current project state (called by autocmds)
local function save_current_project_state()
	-- Only save if a project is actively loaded (not just in a project directory)
	if current_loaded_project then
		state.save(current_loaded_project)
	end
end

--- Save only explorer state (called by resize autocmds)
local function save_explorer_state()
	-- Only save if a project is actively loaded
	if current_loaded_project then
		local project_config = config.read(current_loaded_project)
		if not project_config.ui then
			project_config.ui = {}
		end

		local explorer_info = ui.get_explorer_info()
		project_config.ui.explorer_open = explorer_info.open
		if explorer_info.width then
			project_config.ui.explorer_width = explorer_info.width
		end

		config.write(current_loaded_project, project_config)
	end
end

--- Auto-load project on startup
local function auto_load_project()
	-- Defer to let Neovim complete initialization (syntax, etc.)
	vim.defer_fn(function()
		local args = vim.fn.argv()
		local cwd = vim.fn.getcwd()

		if #args == 0 then
			-- Started with just `nvim` - check if current dir has .easy/easy.json (or old .easy.json)
			local new_config_path = cwd .. "/.easy/easy.json"
			local old_config_path = cwd .. "/.easy.json"

			if vim.fn.filereadable(new_config_path) == 1 or vim.fn.filereadable(old_config_path) == 1 then
				-- Auto-add to projects list if not already there
				if not config.is_tracked_project(cwd) then
					require("easy-projects.projects").add(cwd)
				end
				current_loaded_project = cwd
				state.restore(cwd)
			end
		elseif #args == 1 then
			-- Started with one argument
			local arg = args[1]
			local expanded_arg = vim.fn.expand(arg)

			if vim.fn.isdirectory(expanded_arg) == 1 then
				-- Check if it has .easy/easy.json or .easy.json and auto-add if not tracked
				local new_config_path = expanded_arg .. "/.easy/easy.json"
				local old_config_path = expanded_arg .. "/.easy.json"

				if
					(vim.fn.filereadable(new_config_path) == 1 or vim.fn.filereadable(old_config_path) == 1)
					and not config.is_tracked_project(expanded_arg)
				then
					require("easy-projects.projects").add(expanded_arg)
				end
				-- Started with `nvim path/dir` - load as project
				current_loaded_project = expanded_arg
				require("easy-projects").switch_to_project(expanded_arg)
			end
			-- If it's a file, do nothing (normal file opening behavior)
		end
	end, 100)
end

--- Disable tracking autocmds (used during project switching)
function M.disable_tracking()
	pcall(vim.api.nvim_del_augroup_by_name, "EasyProjectsTracker")
	pcall(vim.api.nvim_del_augroup_by_name, "EasyProjectsExplorerResize")
end

--- Set the currently loaded project
---@param project_path string|nil Path to the loaded project, or nil to unload
function M.set_loaded_project(project_path)
	current_loaded_project = project_path
end

--- Get the currently loaded project
---@return string|nil project_path Path to the loaded project, or nil if none loaded
function M.get_loaded_project()
	return current_loaded_project
end

--- Enable tracking autocmds
function M.enable_tracking()
	-- Track only essential changes and save project state
	vim.api.nvim_create_autocmd({ "VimLeavePre" }, {
		group = vim.api.nvim_create_augroup("EasyProjectsTracker", { clear = true }),
		callback = function()
			save_current_project_state()
		end,
	})

	-- Track active file changes
	vim.api.nvim_create_autocmd({ "BufEnter" }, {
		group = vim.api.nvim_create_augroup("EasyProjectsActiveTracker", { clear = true }),
		callback = function()
			if current_loaded_project then
				state.update_active_file(current_loaded_project)
			end
		end,
	})

	-- Track explorer resize separately (only for explorer width)
	vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
		group = vim.api.nvim_create_augroup("EasyProjectsExplorerResize", { clear = true }),
		callback = function()
			vim.defer_fn(save_explorer_state, 50)
		end,
	})
end

--- Setup all autocmds
function M.setup()
	-- Auto-load project on startup
	vim.api.nvim_create_autocmd("VimEnter", {
		group = vim.api.nvim_create_augroup("EasyProjectsAutoLoad", { clear = true }),
		callback = auto_load_project,
	})

	-- Enable tracking
	M.enable_tracking()
end

return M
