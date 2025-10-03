---@class EasyProjects.Utils
---@field expand_path fun(path: string): string
---@field is_directory fun(path: string): boolean
---@field escape_path fun(path: string): string
local M = {}

--- Expand path with tilde and environment variables
---@param path string The path to expand
---@return string expanded_path The expanded absolute path
function M.expand_path(path)
	return vim.fn.fnamemodify(vim.fn.expand(path), ":p")
end

--- Check if path is a directory
---@param path string The path to check
---@return boolean is_dir True if path is a directory
function M.is_directory(path)
	return vim.fn.isdirectory(path) == 1
end

--- Check if file is readable
---@param path string The file path to check
---@return boolean is_readable True if file is readable
function M.is_readable(path)
	return vim.fn.filereadable(path) == 1
end

--- Escape path for shell commands
---@param path string The path to escape
---@return string escaped_path The escaped path
function M.escape_path(path)
	return vim.fn.fnameescape(path)
end

--- Get folder name from path
---@param path string The full path
---@return string folder_name The folder name
function M.get_folder_name(path)
	return vim.fn.fnamemodify(M.expand_path(path), ":t")
end

--- Convert absolute path to relative from base directory
---@param abs_path string The absolute path
---@param base_path string The base directory path
---@return string|nil relative_path The relative path or nil if not within base
function M.to_relative_path(abs_path, base_path)
	local abs = vim.fn.fnamemodify(abs_path, ":p")
	local base = vim.fn.fnamemodify(base_path, ":p")

	if abs:find(base, 1, true) == 1 then
		local relative = abs:sub(#base + 1)
		if relative:sub(1, 1) == "/" then
			relative = relative:sub(2)
		end
		return relative
	end

	return nil
end

--- Get all loaded file buffers (including unnamed buffers) in display order
---@return table<integer> buffer_ids List of buffer IDs for loaded files and unnamed buffers
function M.get_file_buffers()
	local buffers = {}

	-- Use default buffer list
	local ordered_bufs = vim.api.nvim_list_bufs()

	-- Filter for loaded file buffers
	for _, buf in ipairs(ordered_bufs) do
		if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
			-- Wrap in pcall to avoid errors during buffer operations
			local success, buftype = pcall(vim.api.nvim_get_option_value, "buftype", { buf = buf })
			if not success then
				goto continue
			end

			-- Only include normal buftype (real files and unnamed buffers)
			if buftype ~= "" then
				goto continue
			end

			-- Exclude picker and other special buffers by filetype
			local ok, filetype = pcall(vim.api.nvim_get_option_value, "filetype", { buf = buf })
			if ok and filetype and filetype ~= "" then
				if filetype:match("snacks") or filetype:match("fzf") or filetype:match("telescope") then
					goto continue
				end
			end

			-- Exclude special buffer names
			local ok2, bufname = pcall(vim.api.nvim_buf_get_name, buf)
			if not ok2 then
				goto continue
			end

			if bufname and (bufname:match("snacks://") or bufname:match("fzf://") or bufname:match("telescope://")) then
				goto continue
			end

			table.insert(buffers, buf)
			::continue::
		end
	end

	return buffers
end

--- Create an empty buffer
---@return integer buffer_id The new buffer ID
function M.create_empty_buffer()
	return vim.api.nvim_create_buf(true, false)
end

--- Switch to buffer
---@param buf integer Buffer ID to switch to
function M.switch_to_buffer(buf)
	vim.api.nvim_set_current_buf(buf)
end

--- Delete buffer safely
---@param buf integer Buffer ID to delete
---@param force? boolean Whether to force delete (default: false)
---@return boolean success True if buffer was deleted successfully
function M.delete_buffer(buf, force)
	force = force or false
	if vim.api.nvim_buf_is_valid(buf) then
		local ok = pcall(vim.api.nvim_buf_delete, buf, { force = force })
		return ok
	end
	return false
end

--- Safely call a function with error handling
---@param func function The function to call
---@param ... any Arguments to pass to the function
---@return boolean success, any result Whether the call succeeded and the result
function M.safe_call(func, ...)
	return pcall(func, ...)
end

return M
