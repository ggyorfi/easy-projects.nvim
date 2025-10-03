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

	-- Save all files in unified structure (preserves order, handles modified and unmodified)
	project_config.files = M.save_files_unified(project_path)

	-- Save active file
	project_config.active_file = M.get_active_file(project_path)

	-- Clear old modified_files field (deprecated)
	project_config.modified_files = nil

	config.write(project_path, project_config)
end

--- Helper: Generate consistent hash for file path
---@param relative_path string The relative path
---@return string hash Consistent hash for this file
local function get_file_diff_hash(relative_path)
	return vim.fn.sha256(relative_path):sub(1, 12)
end

--- Helper: Get file content hash
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

--- Helper: Create diff between original file and modified buffer
---@param file_path string Absolute path to the file
---@param buffer_lines table Lines from the modified buffer
---@return string|nil diff The diff string or nil if creation failed
local function create_diff(file_path, buffer_lines)
	local temp_file = vim.fn.tempname()
	local temp_handle = io.open(temp_file, "w")
	if not temp_handle then
		return nil
	end
	for _, line in ipairs(buffer_lines) do
		temp_handle:write(line .. "\n")
	end
	temp_handle:close()

	local diff_cmd
	if utils.is_readable(file_path) then
		diff_cmd = string.format("diff -u %s %s", vim.fn.shellescape(file_path), vim.fn.shellescape(temp_file))
	else
		diff_cmd = string.format("diff -u /dev/null %s", vim.fn.shellescape(temp_file))
	end

	local diff_output = vim.fn.system(diff_cmd)
	os.remove(temp_file)

	if vim.v.shell_error == 0 or vim.v.shell_error == 1 then
		return diff_output
	else
		return nil
	end
end

--- Save all open files in unified structure (preserves order, handles modified and unmodified)
---@param project_path string The project directory path
---@return table files List of file entries with metadata
function M.save_files_unified(project_path)
	local files = {}
	local file_buffers = utils.get_file_buffers()
	local diffs_dir = config.get_diffs_dir(project_path)

	for _, buf in ipairs(file_buffers) do
		local bufname = vim.api.nvim_buf_get_name(buf)
		local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf })
		local is_modified = vim.api.nvim_get_option_value("modified", { buf = buf })

		-- Skip special buffer types
		if buftype ~= "" and buftype ~= "nofile" then
			goto continue
		end

		local file_entry = {}

		if bufname ~= "" then
			-- Handle named files
			local relative_path = utils.to_relative_path(bufname, project_path)
			if not relative_path then
				goto continue
			end

			file_entry.path = relative_path
			file_entry.is_unnamed = false

			if is_modified then
				-- Save diff for modified file
				local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
				local diff_content = create_diff(bufname, lines)
				if diff_content then
					local diff_hash = get_file_diff_hash(relative_path)
					local diff_file_path = diffs_dir .. "/" .. diff_hash .. ".diff"

					local diff_file = io.open(diff_file_path, "w")
					if diff_file then
						diff_file:write(diff_content)
						diff_file:close()

						file_entry.modified = true
						file_entry.diff_hash = diff_hash
						file_entry.original_hash = get_file_hash(bufname)
					end
				end
			else
				file_entry.modified = false
			end

			table.insert(files, file_entry)
		else
			-- Handle unnamed buffers
			if buftype == "" then
				local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

				-- Skip empty unnamed buffers
				if #lines == 1 and lines[1] == "" then
					goto continue
				end

				-- Generate unique path for unnamed buffer
				local unnamed_id = "unnamed_" .. buf .. "_" .. os.time()
				local unnamed_path = ".__unnamed__/" .. unnamed_id

				file_entry.path = unnamed_path
				file_entry.is_unnamed = true
				file_entry.modified = is_modified

				if is_modified or (#lines > 0 and not (#lines == 1 and lines[1] == "")) then
					-- Save content for unnamed buffer
					local content_hash = vim.fn.sha256(table.concat(lines, "\n")):sub(1, 12)
					local content_file_path = diffs_dir .. "/" .. content_hash .. ".content"

					local content_file = io.open(content_file_path, "w")
					if content_file then
						for _, line in ipairs(lines) do
							content_file:write(line .. "\n")
						end
						content_file:close()

						file_entry.content_hash = content_hash
					end
				end

				table.insert(files, file_entry)
			end
		end

		::continue::
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
			-- Double-check buffer isn't a special buffer before closing
			-- (picker might still be open when this is called)
			local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf })
			local bufname = vim.api.nvim_buf_get_name(buf)
			local filetype = vim.api.nvim_get_option_value("filetype", { buf = buf })

			-- Skip special buffer types (picker, prompt, terminal, etc.)
			if buftype ~= "" then
				goto continue
			end

			-- Skip picker/special filetypes
			if filetype:match("snacks_picker") or filetype:match("snacks_input")
				or filetype:match("fzf") or filetype:match("telescope") then
				goto continue
			end

			-- Skip special buffer names
			if bufname:match("snacks://") or bufname:match("fzf") or bufname:match("telescope") then
				goto continue
			end

			-- Safe to close this buffer
			pcall(vim.api.nvim_buf_delete, buf, { force = true })

			::continue::
		end
	end
end

--- Helper: Apply diff to restore file content
---@param file_path string Absolute path to the file
---@param diff_content string The diff to apply
---@return table|nil lines Restored file lines or nil if failed
local function apply_diff(file_path, diff_content)
	local diff_file = vim.fn.tempname() .. ".diff"
	local diff_handle = io.open(diff_file, "w")
	if not diff_handle then
		return nil
	end
	diff_handle:write(diff_content)
	diff_handle:close()

	local temp_file = vim.fn.tempname()
	if utils.is_readable(file_path) then
		vim.fn.system(string.format("cp %s %s", vim.fn.shellescape(file_path), vim.fn.shellescape(temp_file)))
	else
		local empty_handle = io.open(temp_file, "w")
		if empty_handle then
			empty_handle:close()
		end
	end

	local output_file = vim.fn.tempname() .. ".out"
	local patch_cmd = string.format(
		"patch -u -o %s %s < %s 2>/dev/null",
		vim.fn.shellescape(output_file),
		vim.fn.shellescape(temp_file),
		vim.fn.shellescape(diff_file)
	)

	vim.fn.system(patch_cmd)

	local output_handle = io.open(output_file, "r")
	local patched_content = ""
	if output_handle then
		patched_content = output_handle:read("*all")
		output_handle:close()
	end

	os.remove(output_file)
	os.remove(diff_file)
	os.remove(temp_file)

	if vim.v.shell_error == 0 then
		local lines = vim.split(patched_content, "\n")
		if lines[#lines] == "" then
			table.remove(lines)
		end
		return lines
	else
		return nil
	end
end

--- Restore project state from configuration using unified file structure
---@param project_path string The project directory path
---@return integer files_opened Number of files successfully opened
function M.restore_unified(project_path)
	local project_config = config.read(project_path)
	local diffs_dir = config.get_diffs_dir(project_path)

	-- Restore UI state (explorer) FIRST - but defer it to avoid conflicts
	vim.schedule(function()
		ui.restore_explorer(project_config)
	end)

	-- Check if config has files (could be old or new format)
	if not project_config.files or #project_config.files == 0 then
		ui.ensure_editor_pane(0)
		return 0
	end

	-- Detect format: new unified format has table entries with .path field
	local is_unified_format = type(project_config.files[1]) == "table" and project_config.files[1].path ~= nil

	if not is_unified_format then
		-- Fall back to old restore method
		return M.restore_old_format(project_path, project_config)
	end

	local files_opened = 0
	local first_buf = nil
	local initial_buf = vim.api.nvim_get_current_buf()
	local initial_bufname = vim.api.nvim_buf_get_name(initial_buf)
	local initial_is_empty = initial_bufname == "" and not vim.api.nvim_get_option_value("modified", { buf = initial_buf })

	-- Process all files in order
	for _, file_entry in ipairs(project_config.files) do
		local path = file_entry.path
		local is_unnamed = file_entry.is_unnamed or false
		local modified = file_entry.modified or false

		if is_unnamed then
			-- Restore unnamed buffer
			local buf = vim.api.nvim_create_buf(true, false)
			if buf and buf ~= 0 then
				vim.api.nvim_set_option_value("buftype", "", { buf = buf })

				if file_entry.content_hash then
					-- Load content from file
					local content_file_path = diffs_dir .. "/" .. file_entry.content_hash .. ".content"
					local content_file = io.open(content_file_path, "r")
					if content_file then
						local lines = {}
						for line in content_file:lines() do
							table.insert(lines, line)
						end
						content_file:close()

						vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
						if modified then
							vim.api.nvim_set_option_value("modified", true, { buf = buf })
						end
					end
				end

				files_opened = files_opened + 1
				if not first_buf then
					first_buf = buf
				end
			end
		else
			-- Restore named file
			local full_path = project_path .. "/" .. path

			-- If this is the first file and we have an empty initial buffer, reuse it
			local should_reuse_initial = initial_is_empty and files_opened == 0

			if modified and file_entry.diff_hash then
				-- File has unsaved changes - restore from diff
				local diff_file_path = diffs_dir .. "/" .. file_entry.diff_hash .. ".diff"
				local diff_file = io.open(diff_file_path, "r")

				if diff_file then
					local diff_content = diff_file:read("*all")
					diff_file:close()

					-- Check for conflicts
					local current_hash = get_file_hash(full_path)
					local has_conflict = file_entry.original_hash and current_hash and current_hash ~= file_entry.original_hash

					if has_conflict then
						-- TODO: Handle conflicts with dialog
						-- For now, just open the file and skip the diff
						if utils.is_readable(full_path) then
							vim.cmd("edit " .. utils.escape_path(full_path))
							files_opened = files_opened + 1
						end
					else
						-- Apply diff
						local restored_lines = apply_diff(full_path, diff_content)
						if restored_lines then
							vim.cmd("edit " .. utils.escape_path(full_path))
							local buf = vim.api.nvim_get_current_buf()
							vim.api.nvim_buf_set_lines(buf, 0, -1, false, restored_lines)
							vim.api.nvim_set_option_value("modified", true, { buf = buf })
							files_opened = files_opened + 1
						end
					end
				end
			else
				-- Unmodified file - just open it
				if utils.is_readable(full_path) then
					if should_reuse_initial then
						-- Reuse the initial buffer instead of creating a new one
						vim.api.nvim_buf_set_name(initial_buf, full_path)
						vim.cmd("edit!")
						first_buf = initial_buf
						initial_is_empty = false
					else
						vim.cmd("edit " .. utils.escape_path(full_path))
					end
					files_opened = files_opened + 1
				end
			end
		end
	end

	-- Remember the old buffer before we switch
	local old_buf = vim.api.nvim_get_current_buf()

	-- Switch to the first buffer we created/opened
	if first_buf then
		utils.switch_to_buffer(first_buf)

		-- Delete the old empty buffer if it's different and empty
		if old_buf ~= first_buf and vim.api.nvim_buf_is_valid(old_buf) then
			local old_bufname = vim.api.nvim_buf_get_name(old_buf)
			local old_modified = vim.api.nvim_get_option_value("modified", { buf = old_buf })
			local old_lines = vim.api.nvim_buf_get_lines(old_buf, 0, -1, false)
			local is_empty = #old_lines == 1 and old_lines[1] == ""

			if old_bufname == "" and not old_modified and is_empty then
				pcall(vim.api.nvim_buf_delete, old_buf, { force = true })
			end
		end
	elseif files_opened == 0 then
		-- Ensure we have an editor pane if nothing was opened
		ui.ensure_editor_pane(0)
	end

	-- Restore active file after a short delay
	vim.defer_fn(function()
		ui.restore_active_file(project_path, project_config.active_file, files_opened)
	end, 100)

	return files_opened
end

--- Restore project state from old configuration format (for backward compatibility)
---@param project_path string The project directory path
---@param project_config table The project configuration
---@return integer files_opened Number of files successfully opened
function M.restore_old_format(project_path, project_config)
	-- Restore UI state (explorer) FIRST to avoid dialog interference
	ui.restore_explorer(project_config)

	-- Restore regular files
	local files_opened = ui.open_files(project_path, project_config.files or {})

	-- Check if there are modified files (including unnamed buffers) to be restored
	local has_modified_files = project_config.modified_files and next(project_config.modified_files) ~= nil

	-- Ensure we have an editor pane (only if no files opened AND no modified files to restore)
	if files_opened == 0 and not has_modified_files then
		ui.ensure_editor_pane(files_opened)
	end

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

--- Restore project state from configuration (dispatches to unified or old format)
---@param project_path string The project directory path
---@return integer files_opened Number of files successfully opened
function M.restore(project_path)
	return M.restore_unified(project_path)
end

return M
