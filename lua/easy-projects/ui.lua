---@class EasyProjects.UI
---@field get_explorer_info fun(): {open: boolean, width: integer?}
---@field restore_explorer fun(config: table): nil
---@field restore_active_file fun(project_path: string, active_file: string?, files_opened: integer): nil
local M = {}

local utils = require("easy-projects.utils")

--- Get current explorer state information
---@return {open: boolean, width: integer?} explorer_info
function M.get_explorer_info()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		local ok, filetype = pcall(vim.api.nvim_get_option_value, "filetype", { buf = buf })
		if not ok then
			goto continue
		end

		local bufname = vim.api.nvim_buf_get_name(buf)

		-- Check multiple possible snacks explorer identifiers
		if
			filetype == "snacks_explorer"
			or filetype == "snacks_layout_box"
			or bufname:match("snacks://")
			or bufname:match("explorer")
		then
			local width = vim.api.nvim_win_get_width(win)
			return { open = true, width = width }
		end

		::continue::
	end
	return { open = false, width = nil }
end

--- Check if plugin windows are open that should not be disturbed
---@return boolean should_skip True if explorer restoration should be skipped
local function should_skip_explorer_restoration()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		local bufname = vim.api.nvim_buf_get_name(buf)
		local ok, filetype = pcall(vim.api.nvim_get_option_value, "filetype", { buf = buf })

		if ok then
			-- Skip if Lazy window is open
			if filetype == "lazy" or bufname:match("lazy") then
				return true
			end

			-- Skip if other plugin managers are open
			if filetype:match("mason") or filetype:match("lspinfo") or filetype:match("help") then
				return true
			end
		end
	end
	return false
end

--- Store pending explorer config for later restoration
local pending_explorer_config = nil

--- Restore explorer state from configuration
---@param config table Project configuration containing UI state
function M.restore_explorer(config)
	if not _G.Snacks or not _G.Snacks.explorer then
		return
	end

	-- Skip restoration if plugin windows are open, but store config for later
	if should_skip_explorer_restoration() then
		pending_explorer_config = config

		-- Set up autocommand to restore when plugin windows close
		vim.api.nvim_create_autocmd({ "WinClosed", "BufWinLeave" }, {
			group = vim.api.nvim_create_augroup("EasyProjectsDelayedRestore", { clear = true }),
			callback = function()
				-- Small delay to let window closing complete
				vim.defer_fn(function()
					if pending_explorer_config and not should_skip_explorer_restoration() then
						M.restore_explorer_now(pending_explorer_config)
						pending_explorer_config = nil
						-- Clean up the autocommand
						pcall(vim.api.nvim_del_augroup_by_name, "EasyProjectsDelayedRestore")
					end
				end, 100)
			end,
		})
		return
	end

	M.restore_explorer_now(config)
end

--- Actually perform the explorer restoration
---@param config table Project configuration containing UI state
function M.restore_explorer_now(config)
	local desired_open = config.ui and config.ui.explorer_open or false
	local desired_width = config.ui and config.ui.explorer_width
	local current_info = M.get_explorer_info()

	if current_info.open then
		if desired_open then
			-- Explorer open, should stay open - resize if width differs
			if desired_width and current_info.width ~= desired_width then
				for _, win in ipairs(vim.api.nvim_list_wins()) do
					local buf = vim.api.nvim_win_get_buf(win)
					local ok, filetype = pcall(vim.api.nvim_get_option_value, "filetype", { buf = buf })
					if ok and filetype == "snacks_layout_box" then
						vim.api.nvim_win_set_width(win, desired_width)
						break
					end
				end
			end
		else
			-- Explorer open, should be closed
			_G.Snacks.explorer()
		end
	else
		if desired_open then
			-- Explorer closed, should be opened
			if desired_width then
				local success = pcall(_G.Snacks.explorer, {
					layout = { layout = { width = desired_width } },
				})
				if not success then
					_G.Snacks.explorer()
				end
			else
				_G.Snacks.explorer()
			end
		end
		-- Explorer closed, should stay closed - do nothing
	end
end

--- Open files from file list (including unnamed buffer tabs)
---@param project_path string The project directory path
---@param files table List of relative file paths and unnamed buffer identifiers
---@return integer files_opened Number of files successfully opened
function M.open_files(project_path, files)
	if not files or #files == 0 then
		return 0
	end

	local files_opened = 0
	for _, file_path in ipairs(files) do
		if file_path:match("^.__unnamed_tab__/") then
			-- Create empty unnamed buffer for tab restoration
			local buf = vim.api.nvim_create_buf(true, false)
			if buf and buf ~= 0 then
				vim.api.nvim_set_option_value("buftype", "", { buf = buf })
				files_opened = files_opened + 1
			end
		else
			-- Handle regular named files
			local full_path = project_path .. "/" .. file_path
			if utils.is_readable(full_path) then
				vim.cmd("edit " .. utils.escape_path(full_path))
				files_opened = files_opened + 1
			end
		end
	end

	return files_opened
end

--- Restore the active file from saved state
---@param project_path string The project directory path
---@param active_file string? Relative path to the file that should be active, or "__unnamed__" for unnamed buffer
---@param files_opened integer Number of files that were opened
function M.restore_active_file(project_path, active_file, files_opened)
	if not active_file then
		return
	end

	-- Handle unnamed buffer activation
	if active_file:match("^__unnamed__") then
		-- Extract content hash from active_file (format: "__unnamed__:hash" or just "__unnamed__")
		local target_hash = active_file:match("^__unnamed__:(.+)$")

		if target_hash then
			-- Find the specific unnamed buffer by content hash
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if vim.api.nvim_buf_is_loaded(buf) then
					local bufname = vim.api.nvim_buf_get_name(buf)
					local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf })
					if bufname == "" and buftype == "" then
						-- Check if this buffer's content matches the target hash
						local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
						local content_hash = vim.fn.sha256(table.concat(lines, "\n")):sub(1, 12)
						if content_hash == target_hash then
							utils.switch_to_buffer(buf)
							M.focus_editor_window()
							return
						end
					end
				end
			end
		else
			-- Fallback for old format (just "__unnamed__") - find the first unnamed buffer
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if vim.api.nvim_buf_is_loaded(buf) then
					local bufname = vim.api.nvim_buf_get_name(buf)
					local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf })
					if bufname == "" and buftype == "" then
						utils.switch_to_buffer(buf)
						M.focus_editor_window()
						return
					end
				end
			end
		end
		return
	end

	-- Handle named file activation (existing logic)
	if files_opened == 0 then
		return
	end

	local full_path = project_path .. "/" .. active_file

	-- Check if file exists and is readable
	if utils.is_readable(full_path) then
		-- Find buffer for this file and switch to it
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(buf) then
				local bufname = vim.api.nvim_buf_get_name(buf)
				if bufname == full_path then
					utils.switch_to_buffer(buf)
					M.focus_editor_window()
					return
				end
			end
		end

		-- If buffer not found, open the file (it might not have been in the files list)
		vim.cmd("edit " .. utils.escape_path(full_path))
		M.focus_editor_window()
	end
end

--- Focus the editor window (move cursor away from explorer)
function M.focus_editor_window()
	-- Find the first non-explorer window and focus it
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		local ok, filetype = pcall(vim.api.nvim_get_option_value, "filetype", { buf = buf })
		if ok then
			-- Skip explorer windows
			if not (filetype == "snacks_explorer" or filetype == "snacks_layout_box") then
				local bufname = vim.api.nvim_buf_get_name(buf)
				-- Also skip snacks:// buffers and other special buffers
				if not (bufname:match("snacks://") or bufname:match("explorer")) then
					vim.api.nvim_set_current_win(win)
					return
				end
			end
		end
	end
end

--- Create empty buffer if needed (when no files to restore)
---@param files_opened integer Number of files that were opened
---@return integer? buffer_id The empty buffer ID if created
function M.ensure_editor_pane(files_opened)
	if files_opened == 0 then
		-- Check if current buffer is already a suitable empty buffer
		local current_buf = vim.api.nvim_get_current_buf()
		local bufname = vim.api.nvim_buf_get_name(current_buf)
		local buftype = vim.bo[current_buf].buftype

		-- If current buffer is already an unnamed, normal buffer, use it
		if bufname == "" and buftype == "" and not vim.bo[current_buf].modified then
			return current_buf
		end

		-- Otherwise, create a new empty buffer
		local empty_buf = utils.create_empty_buffer()
		utils.switch_to_buffer(empty_buf)
		return empty_buf
	end
	return nil
end

return M
