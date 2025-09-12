---@class EasyProjects.Utils
---@field expand_path fun(path: string): string
---@field is_directory fun(path: string): boolean
---@field escape_path fun(path: string): string
local M = {}

--- Expand path with tilde and environment variables
---@param path string The path to expand
---@return string expanded_path The expanded absolute path
function M.expand_path(path)
	return vim.fn.expand(path)
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

--- Get all loaded file buffers
---@return table<integer> buffer_ids List of buffer IDs for loaded files
function M.get_file_buffers()
	local buffers = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) then
			local bufname = vim.api.nvim_buf_get_name(buf)
			local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf })

			-- Only include real files (not special buffers)
			if bufname ~= "" and buftype == "" then
				table.insert(buffers, buf)
			end
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
