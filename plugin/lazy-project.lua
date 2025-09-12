-- Plugin entry point for easy-projects.nvim
-- This file is automatically sourced when the plugin loads

if vim.g.loaded_easy_projects then
	return
end
vim.g.loaded_easy_projects = 1

-- Custom completion function for directories
local function complete_directories(arg_lead, cmd_line, cursor_pos)
	return vim.fn.glob(arg_lead .. "*", false, true)
end

-- Create user commands
vim.api.nvim_create_user_command("EasyOpenProjects", function()
	require("easy-projects").pick_project()
end, { desc = "Open project picker" })

vim.api.nvim_create_user_command("EasyAddProject", function(opts)
	local path = opts.args ~= "" and opts.args or vim.fn.getcwd()
	require("easy-projects").add_project(path)
end, {
	desc = "Add current or specified directory as project",
	nargs = "?",
	complete = complete_directories,
})

vim.api.nvim_create_user_command("EasyEditProjects", function()
	require("easy-projects").edit_projects()
end, { desc = "Edit projects file" })

-- Easy commands for common tasks
vim.api.nvim_create_user_command("EasyQuit", function()
	vim.cmd("qa!")
end, { desc = "Quit Neovim without saving" })

vim.api.nvim_create_user_command("EasyCloseAllSaved", function()
	local buffers = vim.api.nvim_list_bufs()
	local closed_any = false

	for _, buf in ipairs(buffers) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_is_valid(buf) then
			local buftype = vim.bo[buf].buftype
			local filetype = vim.bo[buf].filetype
			local buflisted = vim.bo[buf].buflisted
			local modified = vim.bo[buf].modified

			-- Only close regular files that are unmodified and listed
			-- Skip special buffers (terminal, help, quickfix, etc.) and snacks buffers
			if
				buflisted
				and not modified
				and buftype == ""
				and not string.match(filetype, "^snacks_")
				and filetype ~= "help"
				and filetype ~= "qf"
			then
				vim.api.nvim_buf_delete(buf, {})
				closed_any = true
			end
		end
	end

	-- If we closed buffers and no regular buffers remain listed, create a new empty buffer
	if closed_any then
		local remaining_regular_bufs = vim.tbl_filter(function(buf)
			if not (vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted) then
				return false
			end
			local buftype = vim.bo[buf].buftype
			local filetype = vim.bo[buf].filetype
			return buftype == "" and not string.match(filetype, "^snacks_")
		end, vim.api.nvim_list_bufs())

		if #remaining_regular_bufs == 0 then
			vim.cmd("enew")
		end
	end
end, { desc = "Close all unmodified buffers" })

vim.api.nvim_create_user_command("EasyToggleExplorer", function()
	-- Get saved explorer width from project config
	local cwd = vim.fn.getcwd()
	local config = require("easy-projects.config").read(cwd)
	local saved_width = config.ui and config.ui.explorer_width

	if not _G.Snacks or not _G.Snacks.explorer then
		vim.notify("Snacks explorer not available", vim.log.levels.WARN)
		return
	end

	if saved_width then
		-- Open explorer with saved width
		_G.Snacks.explorer({
			layout = {
				layout = {
					width = saved_width,
				},
			},
		})
	else
		-- Fallback to default
		_G.Snacks.explorer()
	end
end, { desc = "Toggle explorer with saved width" })

-- Yank current file path (relative to CWD)
vim.api.nvim_create_user_command("EasyYankPath", function()
	local path = nil
	
	-- Check if we're in Snacks explorer
	if vim.bo.filetype == "snacks_picker_list" then
		-- Try to get the current item from Snacks picker
		if _G.Snacks and _G.Snacks.picker then
			local picker = _G.Snacks.picker.get()
			if picker and picker[1] and picker[1].list and picker[1].list._current then
				local current_item = picker[1].list._current
				if current_item and current_item.file then
					path = vim.fn.fnamemodify(current_item.file, ":.")
				end
			end
		end
	else
		-- Regular buffer - get current file path
		path = vim.fn.expand("%")
	end
	
	if not path or path == "" then
		vim.notify("No file or folder to yank path from", vim.log.levels.WARN)
		return
	end
	
	vim.fn.setreg("+", path)
	vim.notify("Yanked path: " .. path)
end, { desc = "Yank current file/folder path (relative)" })

-- Yank absolute path
vim.api.nvim_create_user_command("EasyYankAbsPath", function()
	local path = nil
	
	-- Check if we're in Snacks explorer
	if vim.bo.filetype == "snacks_picker_list" then
		-- Try to get the current item from Snacks picker
		if _G.Snacks and _G.Snacks.picker then
			local picker = _G.Snacks.picker.get()
			if picker and picker[1] and picker[1].list and picker[1].list._current then
				local current_item = picker[1].list._current
				if current_item and current_item.file then
					path = current_item.file  -- Already absolute
				end
			end
		end
		
	else
		-- Regular buffer - get current file absolute path
		path = vim.fn.expand("%:p")
	end
	
	if not path or path == "" then
		vim.notify("No file or folder to yank path from", vim.log.levels.WARN)
		return
	end
	
	vim.fn.setreg("+", path)
	vim.notify("Yanked absolute path: " .. path)
end, { desc = "Yank current file/folder absolute path" })

-- Create autocmd group for plugin events
vim.api.nvim_create_augroup("EasyProjects", { clear = true })

-- Initialize the plugin
require("easy-projects").setup()
