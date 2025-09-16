---@class EasyProjects.State
---@field save fun(project_path: string): nil
---@field save_files fun(project_path: string): table
---@field close_old_buffers fun(buffer_ids: table): nil
local M = {}

local utils = require("easy-projects.utils")
local config = require("easy-projects.config")
local ui = require("easy-projects.ui")
local diffs = require("easy-projects.diffs")

--- Update the tracked active file when a file buffer becomes active
---@param project_path string The project directory path
function M.update_active_file(project_path)
	local current_buf = vim.api.nvim_get_current_buf()
	local bufname = vim.api.nvim_buf_get_name(current_buf)

	-- Only track if current buffer is a file in this project
	if bufname ~= "" then
		local relative_path = utils.to_relative_path(bufname, project_path)
		if relative_path then
			-- Store in config immediately
			local project_config = config.read(project_path)
			project_config.active_file = relative_path
			config.write(project_path, project_config)
		end
	end
end

--- Save current project state (UI and files)
---@param project_path string The project directory path
function M.save(project_path)
	local project_config = config.read(project_path)
	if not project_config.ui then
		project_config.ui = {}
	end

	-- Save explorer state
	local explorer_info = ui.get_explorer_info()
	project_config.ui.explorer_open = explorer_info.open
	if explorer_info.width then
		project_config.ui.explorer_width = explorer_info.width
	end

	-- Save open files (non-modified)
	project_config.files = M.save_files(project_path)

	-- Save active file
	project_config.active_file = M.get_active_file(project_path)

	-- Save modified files as diffs (only metadata in config)
	project_config.modified_files = diffs.save_modified_as_diffs(project_path)

	config.write(project_path, project_config)
end

--- Get list of open files relative to project path (including unnamed buffers)
---@param project_path string The project directory path
---@return table files List of relative file paths and unnamed buffer identifiers
function M.save_files(project_path)
	local files = {}
	local file_buffers = utils.get_file_buffers()

	for _, buf in ipairs(file_buffers) do
		local bufname = vim.api.nvim_buf_get_name(buf)
		local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf })

		if bufname ~= "" then
			-- Handle named files
			local relative_path = utils.to_relative_path(bufname, project_path)
			if relative_path then
				table.insert(files, relative_path)
			end
		else
			-- Handle unnamed buffers (for tab restoration)
			if buftype == "" then
				-- Generate a unique identifier for tab restoration
				local unnamed_id = "unnamed_" .. buf .. "_" .. os.time()
				local unnamed_path = ".__unnamed_tab__/" .. unnamed_id
				table.insert(files, unnamed_path)
			end
		end
	end

	return files
end

--- Get the last active file relative to project path
--- Returns the tracked active file, or current buffer if it's a project file, or special marker for unnamed
---@param project_path string The project directory path
---@return string? active_file Relative path of active file, "__unnamed__" for unnamed buffer, or nil if none tracked
function M.get_active_file(project_path)
	local current_buf = vim.api.nvim_get_current_buf()
	local bufname = vim.api.nvim_buf_get_name(current_buf)
	local buftype = vim.api.nvim_get_option_value("buftype", { buf = current_buf })

	-- Check if current buffer is an unnamed buffer
	if bufname == "" and buftype == "" then
		-- Get content hash to identify this specific unnamed buffer
		local lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
		local content_hash = vim.fn.sha256(table.concat(lines, "\n")):sub(1, 12)

		-- Store special marker with content hash for unnamed buffer
		local project_config = config.read(project_path)
		project_config.active_file = "__unnamed__:" .. content_hash
		config.write(project_path, project_config)
		return "__unnamed__:" .. content_hash
	end

	-- First, update tracking with current buffer if it's a project file
	M.update_active_file(project_path)

	-- Return the active file from config
	local project_config = config.read(project_path)
	return project_config.active_file
end

--- Get list of current file buffer IDs for closing later
---@return table buffer_ids List of buffer IDs to close
function M.get_old_buffers()
	return utils.get_file_buffers()
end

--- Close old project buffers forcefully (after saving modified state)
---@param buffer_ids table List of buffer IDs to close
function M.close_old_buffers(buffer_ids)
	-- Force close buffers without prompting (diffs already saved)
	for _, buf in ipairs(buffer_ids) do
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end
end

--- Restore project state from configuration
---@param project_path string The project directory path
---@return integer files_opened Number of files successfully opened
function M.restore(project_path)
	local project_config = config.read(project_path)

	-- Restore UI state (explorer) FIRST to avoid dialog interference
	ui.restore_explorer(project_config)

	-- Restore regular files
	local files_opened = ui.open_files(project_path, project_config.files or {})

	-- Ensure we have an editor pane
	ui.ensure_editor_pane(files_opened)

	-- Restore modified files from diffs with conflict resolution (deferred to avoid UI conflicts)
	vim.defer_fn(function()
		diffs.restore_from_diffs(project_path, project_config.modified_files)

		-- Restore active file AFTER diffs are restored (so unnamed buffers exist)
		vim.defer_fn(function()
			ui.restore_active_file(project_path, project_config.active_file, files_opened)
		end, 50) -- Small additional delay after diffs restoration
	end, 200) -- 200ms delay to let UI settle

	return files_opened
end

return M
