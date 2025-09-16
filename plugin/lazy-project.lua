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

-- Tab/buffer management commands
vim.api.nvim_create_user_command("EasyCloseBuffer", function(opts)
	if opts.bang then
		require("easy-projects").force_close_tab()
	else
		require("easy-projects").close_tab()
	end
end, {
	desc = "Close current buffer (use ! to force)",
	bang = true
})

-- Easy commands for common tasks
vim.api.nvim_create_user_command("EasyQuit", function()
	vim.cmd("qa!")
end, { desc = "Quit Neovim without saving" })

vim.api.nvim_create_user_command("EasyCloseAllSaved", function()
	-- 1. Get the list of all files
	local buffers = vim.api.nvim_list_bufs()
	
	-- 2. Get the list of files to close
	local buffers_to_close = {}
	local regular_buffers = {} -- All regular buffers (to check if we're closing all of them)
	
	for _, buf in ipairs(buffers) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_is_valid(buf) then
			local buftype = vim.bo[buf].buftype
			local filetype = vim.bo[buf].filetype
			local buflisted = vim.bo[buf].buflisted
			local modified = vim.bo[buf].modified
			
			-- Check if this is a regular buffer
			if buflisted and buftype == "" 
				and not string.match(filetype or "", "^snacks_")
				and filetype ~= "help"
				and filetype ~= "qf"
				and filetype ~= "snacks_picker_list"
				and filetype ~= "snacks_layout_box"
				and filetype ~= "snacks_explorer"
				and buftype ~= "nofile"
				and buftype ~= "prompt"
				and not string.match(buftype or "", "nowrite")
			then
				table.insert(regular_buffers, buf)
				-- Only close if unmodified
				if not modified then
					table.insert(buffers_to_close, buf)
				end
			end
		end
	end
	
	-- 3. If we are going to close all files then create a noname file
	if #buffers_to_close == #regular_buffers and #buffers_to_close > 0 then
		local current_ft = vim.bo.filetype
		local in_explorer = current_ft == "snacks_picker_list" or current_ft == "snacks_layout_box" or string.match(current_ft or "", "^snacks_")
		
		-- Find the main window to create the new buffer in
		local main_win = nil
		if in_explorer then
			-- From explorer: find main window
			for _, win in ipairs(vim.api.nvim_list_wins()) do
				local buf = vim.api.nvim_win_get_buf(win)
				local win_ft = vim.bo[buf].filetype
				if not string.match(win_ft or "", "^snacks_") and win_ft ~= "snacks_picker_list" and win_ft ~= "snacks_layout_box" then
					main_win = win
					break
				end
			end
		else
			-- From regular buffer: use current window
			main_win = vim.api.nvim_get_current_win()
		end
		
		-- Create new buffer in main window before closing others
		if main_win then
			vim.api.nvim_set_current_win(main_win)
			vim.cmd("enew")
		end
	end
	
	-- 4. Close the files that need to be closed
	for _, buf in ipairs(buffers_to_close) do
		vim.api.nvim_buf_delete(buf, {})
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
