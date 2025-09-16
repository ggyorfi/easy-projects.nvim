---@class EasyProjects.Diffs
---@field save_modified_as_diffs fun(project_path: string): table
---@field restore_from_diffs fun(project_path: string, modified_files: table): nil
local M = {}

local utils = require("easy-projects.utils")
local config = require("easy-projects.config")
local dialogs = require("easy-projects.dialogs")

--- Generate a consistent hash for the file (for cleanup)
---@param relative_path string The relative path to the file
---@return string file_hash Consistent hash for this file
local function get_file_diff_hash(relative_path)
	return vim.fn.sha256(relative_path):sub(1, 12) -- First 12 chars for shorter filename
end

--- Get file content hash for conflict detection
---@param file_path string Absolute path to the file
---@return string|nil hash SHA256 hash of file content or nil if file doesn't exist
local function get_file_hash(file_path)
	if not utils.is_readable(file_path) then
		return nil
	end

	local file = io.open(file_path, "r")
	if not file then
		return nil
	end

	local content = file:read("*all")
	file:close()

	return vim.fn.sha256(content)
end

--- Create diff between original file and modified buffer
---@param file_path string Absolute path to the file
---@param buffer_lines table Lines from the modified buffer
---@return string|nil diff The diff string or nil if creation failed
local function create_diff(file_path, buffer_lines)
	-- Write buffer content to temporary file
	local temp_file = vim.fn.tempname()
	local temp_handle = io.open(temp_file, "w")
	if not temp_handle then
		return nil
	end

	for _, line in ipairs(buffer_lines) do
		temp_handle:write(line .. "\n")
	end
	temp_handle:close()

	-- Generate diff using system diff command
	local diff_cmd
	if utils.is_readable(file_path) then
		-- File exists, create normal diff
		diff_cmd = string.format("diff -u %s %s", vim.fn.shellescape(file_path), vim.fn.shellescape(temp_file))
	else
		-- New file, create diff from /dev/null
		diff_cmd = string.format("diff -u /dev/null %s", vim.fn.shellescape(temp_file))
	end

	local diff_output = vim.fn.system(diff_cmd)

	-- Clean up temp file
	os.remove(temp_file)

	-- diff command returns exit code 1 for differences, which is normal
	if vim.v.shell_error == 0 or vim.v.shell_error == 1 then
		return diff_output
	else
		return nil
	end
end

--- Apply diff to restore file content
---@param file_path string Absolute path to the file
---@param diff_content string The diff to apply
---@return table|nil lines Restored file lines or nil if failed
local function apply_diff(file_path, diff_content)
	-- Write diff to temporary file
	local diff_file = vim.fn.tempname() .. ".diff"
	local diff_handle = io.open(diff_file, "w")
	if not diff_handle then
		return nil
	end
	diff_handle:write(diff_content)
	diff_handle:close()

	-- Create temporary copy of original file
	local temp_file = vim.fn.tempname()
	if utils.is_readable(file_path) then
		vim.fn.system(string.format("cp %s %s", vim.fn.shellescape(file_path), vim.fn.shellescape(temp_file)))
	else
		-- Create empty file for new files
		local empty_handle = io.open(temp_file, "w")
		if empty_handle then
			empty_handle:close()
		end
	end

	-- Apply diff using patch command to output file (avoids stdout messages)
	local output_file = vim.fn.tempname() .. ".out"
	local patch_cmd = string.format(
		"patch -u -o %s %s < %s 2>/dev/null",
		vim.fn.shellescape(output_file),
		vim.fn.shellescape(temp_file),
		vim.fn.shellescape(diff_file)
	)

	vim.fn.system(patch_cmd)

	-- Read the patched content from output file
	local output_handle = io.open(output_file, "r")
	local patched_content = ""
	if output_handle then
		patched_content = output_handle:read("*all")
		output_handle:close()
	end

	-- Clean up output file
	os.remove(output_file)

	-- Clean up temp files
	os.remove(diff_file)
	os.remove(temp_file)

	if vim.v.shell_error == 0 then
		-- Split content into lines
		local lines = vim.split(patched_content, "\n")
		-- Remove last empty line if it exists (common with patch output)
		if lines[#lines] == "" then
			table.remove(lines)
		end
		return lines
	else
		return nil
	end
end

--- Save modified buffers as diffs
---@param project_path string The project directory path
---@return table modified_files Information about modified files (hash only)
function M.save_modified_as_diffs(project_path)
	local modified_files = {}
	local file_buffers = utils.get_file_buffers()
	local diffs_dir = config.get_diffs_dir(project_path)

	for _, buf in ipairs(file_buffers) do
		local is_modified = vim.api.nvim_get_option_value("modified", { buf = buf })
		local bufname = vim.api.nvim_buf_get_name(buf)
		local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf })


		if vim.api.nvim_buf_is_valid(buf) and is_modified then

			-- Skip special buffer types (terminal, help, etc.)
			if buftype ~= "" and buftype ~= "nofile" then
				goto continue
			end

			if bufname ~= "" then
				-- Handle named files
				local relative_path = utils.to_relative_path(bufname, project_path)
				if relative_path then
					-- Get buffer content
					local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

					-- Get original file hash for conflict detection
					local original_hash = get_file_hash(bufname)

					-- Create diff
					local diff_content = create_diff(bufname, lines)
					if diff_content then
						-- Generate consistent hash for this file (enables cleanup)
						local diff_hash = get_file_diff_hash(relative_path)
						local diff_file_path = diffs_dir .. "/" .. diff_hash .. ".diff"

						-- Write diff to file
						local diff_file = io.open(diff_file_path, "w")
						if diff_file then
							diff_file:write(diff_content)
							diff_file:close()

							-- Store only metadata in config
							modified_files[relative_path] = {
								diff_hash = diff_hash,
								original_hash = original_hash,
								timestamp = os.time(),
							}
						end
					end
				end
			else
				-- Handle unnamed buffers
				local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

				-- Skip empty unnamed buffers
				if #lines == 1 and lines[1] == "" then
					goto continue
				end

				-- Generate a unique name for this unnamed buffer
				local unnamed_id = "unnamed_" .. buf .. "_" .. os.time()
				local unnamed_path = ".__unnamed__/" .. unnamed_id

				-- Store content directly (no diff needed for unnamed buffers)
				local content_hash = vim.fn.sha256(table.concat(lines, "\n")):sub(1, 12)
				local content_file_path = diffs_dir .. "/" .. content_hash .. ".content"

				-- Write content to file
				local content_file = io.open(content_file_path, "w")
				if content_file then
					for _, line in ipairs(lines) do
						content_file:write(line .. "\n")
					end
					content_file:close()

					-- Store metadata for unnamed buffer
					modified_files[unnamed_path] = {
						content_hash = content_hash,
						is_unnamed = true,
						buf_id = buf,
						timestamp = os.time(),
					}
				end
			end
		end
		::continue::
	end

	return modified_files
end

--- Check conflict type for a file
---@param file_path string Absolute path to the file
---@param stored_hash string|nil Hash stored when we saved the modified state
---@return string conflict_type "none", "modified", or "deleted"
local function get_conflict_type(file_path, stored_hash)
	if not stored_hash then
		return "none" -- No original hash means file was new
	end

	if not utils.is_readable(file_path) then
		return "deleted" -- File was deleted
	end

	local current_hash = get_file_hash(file_path)
	if current_hash ~= stored_hash then
		return "modified" -- File was changed
	end

	return "none" -- No conflict
end

--- Restore modified files from diff files
---@param project_path string The project directory path
---@param modified_files table Saved modified files metadata
function M.restore_from_diffs(project_path, modified_files)
	if not modified_files or vim.tbl_isempty(modified_files) then
		return
	end

	local diffs_dir = config.get_diffs_dir(project_path)

	-- First pass: collect conflicts and valid files
	local conflicts = {}
	local valid_files = {}

	for relative_path, file_data in pairs(modified_files) do
		-- Handle unnamed buffers (no conflicts possible)
		if file_data.is_unnamed then
			valid_files[relative_path] = file_data
			goto continue
		end

		local absolute_path = project_path .. "/" .. relative_path

		-- Skip if this is old format (has 'lines' instead of 'diff_hash')
		if file_data.lines and not file_data.diff_hash then
			goto continue
		end

		-- Skip if diff_hash is missing
		if not file_data.diff_hash then
			goto continue
		end

		-- Check for conflicts
		local conflict_type = get_conflict_type(absolute_path, file_data.original_hash)
		if conflict_type ~= "none" then
			conflicts[relative_path] = conflict_type
		else
			valid_files[relative_path] = file_data
		end

		::continue::
	end

	-- Handle conflicts with modern dialog UI
	if vim.tbl_count(conflicts) > 0 then
		-- Use async dialog - we need to make this function async
		dialogs.show_batch_conflicts(conflicts, function(conflict_resolutions)
			-- Process the resolutions
			M.process_conflict_resolutions(project_path, modified_files, conflicts, conflict_resolutions, valid_files)
		end)
	else
		-- No conflicts, restore directly
		M.restore_valid_files(project_path, valid_files)
	end
end

--- Process conflict resolutions and restore files
---@param project_path string The project directory path
---@param modified_files table Original modified files metadata
---@param conflicts table The conflicts that were resolved
---@param conflict_resolutions table User's conflict resolutions
---@param valid_files table Files without conflicts
function M.process_conflict_resolutions(project_path, modified_files, conflicts, conflict_resolutions, valid_files)
	-- Add resolved conflicts to valid files if user chose "stashed"
	for relative_path, resolution in pairs(conflict_resolutions) do
		if resolution == "stashed" then
			valid_files[relative_path] = modified_files[relative_path]
		end
		-- "disk" and "skip" are handled by not adding to valid_files
	end

	-- Restore all valid files
	M.restore_valid_files(project_path, valid_files)
end

--- Restore valid files (no conflicts or resolved)
---@param project_path string The project directory path
---@param valid_files table Files to restore
function M.restore_valid_files(project_path, valid_files)
	local diffs_dir = config.get_diffs_dir(project_path)

	for relative_path, file_data in pairs(valid_files) do
		if file_data.is_unnamed then
			-- Handle unnamed buffer restoration
			local content_file_path = diffs_dir .. "/" .. file_data.content_hash .. ".content"
			local content_file = io.open(content_file_path, "r")
			if not content_file then
				goto continue_restore
			end

			local content = content_file:read("*all")
			content_file:close()

			-- Split content into lines
			local lines = vim.split(content, "\n")
			-- Remove last empty line if it exists
			if lines[#lines] == "" then
				table.remove(lines)
			end

			-- Try to find an existing empty unnamed buffer first (from tab restoration)
			local target_buf = nil
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if vim.api.nvim_buf_is_loaded(buf) then
					local bufname = vim.api.nvim_buf_get_name(buf)
					local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf })
					local is_modified = vim.api.nvim_get_option_value("modified", { buf = buf })
					if bufname == "" and buftype == "" and not is_modified then
						-- Check if buffer is empty
						local existing_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
						if #existing_lines == 1 and existing_lines[1] == "" then
							target_buf = buf
							break
						end
					end
				end
			end

			-- If no empty buffer found, create new one
			if not target_buf then
				target_buf = vim.api.nvim_create_buf(true, false)
				if target_buf and target_buf ~= 0 then
					vim.api.nvim_set_option_value("buftype", "", { buf = target_buf })
				end
			end

			if target_buf and target_buf ~= 0 then
				-- Set the restored content
				vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, lines)

				-- Mark as modified
				vim.api.nvim_set_option_value("modified", true, { buf = target_buf })
			end
		else
			-- Handle named file restoration (existing logic)
			local absolute_path = project_path .. "/" .. relative_path

			-- Read diff file
			local diff_file_path = diffs_dir .. "/" .. file_data.diff_hash .. ".diff"
			local diff_file = io.open(diff_file_path, "r")
			if not diff_file then
				goto continue_restore
			end

			local diff_content = diff_file:read("*all")
			diff_file:close()

			-- Apply diff to get restored content
			local restored_lines = apply_diff(absolute_path, diff_content)
			if not restored_lines then
				goto continue_restore
			end

			-- Create or get buffer
			local buf = vim.fn.bufnr(absolute_path, true)

			-- Load the file first if it exists
			if utils.is_readable(absolute_path) then
				vim.api.nvim_buf_call(buf, function()
					vim.cmd("edit " .. vim.fn.fnameescape(absolute_path))
				end)
			end

			-- Set the restored content
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, restored_lines)

			-- Mark as modified
			vim.api.nvim_set_option_value("modified", true, { buf = buf })
		end

		::continue_restore::
	end
end

return M

