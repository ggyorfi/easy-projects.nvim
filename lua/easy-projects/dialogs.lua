---@class EasyProjects.Dialogs
local M = {}

--- Create a conflict resolution dialog using Snacks select
---@param conflicts table<string,string> Map of relative_path -> conflict_type
---@param callback fun(resolutions: table<string,"disk"|"stashed"|"skip">)
function M.show_batch_conflicts(conflicts, callback)
	local conflict_count = vim.tbl_count(conflicts)

	if conflict_count == 0 then
		callback({})
		return
	end

	if conflict_count == 1 then
		M.show_individual_conflicts(conflicts, callback)
		return
	end

	local options = {
		"Use Disk versions (lose stashed changes)",
		"Use Stashed versions (restore modified files)",
		"Review each file individually"
	}

	local prompt = string.format("%d files have conflicts. Choose action:", conflict_count)

	vim.ui.select(options, {
		prompt = prompt,
		format_item = function(item)
			return item
		end,
	}, function(choice)
		if not choice then
			callback({}) -- User cancelled
			return
		end

		local resolutions = {}

		if choice:match("^Use Disk") then
			-- Use disk versions
			for relative_path, _ in pairs(conflicts) do
				resolutions[relative_path] = "disk"
			end
			callback(resolutions)
		elseif choice:match("^Use Stashed") then
			-- Use stashed versions  
			for relative_path, _ in pairs(conflicts) do
				resolutions[relative_path] = "stashed"
			end
			callback(resolutions)
		elseif choice:match("^Review") then
			-- Review each file
			M.show_individual_conflicts(conflicts, callback)
		end
	end)
end

--- Show individual conflict resolution for each file
---@param conflicts table<string,string> Map of relative_path -> conflict_type
---@param callback fun(resolutions: table<string,"disk"|"stashed"|"skip">)
function M.show_individual_conflicts(conflicts, callback)
	local resolutions = {}
	local conflict_files = vim.tbl_keys(conflicts)
	table.sort(conflict_files)
	local current_index = 1

	local function show_next_conflict()
		if current_index > #conflict_files then
			callback(resolutions)
			return
		end

		local relative_path = conflict_files[current_index]
		local conflict_type = conflicts[relative_path]
		local status = conflict_type == "deleted" and " (was deleted)" or " (was modified)"

		local options = {
			"Use Disk version",
			"Use Stashed version", 
			"Skip remaining files"
		}

		local prompt = string.format("File %d/%d: %s%s", 
			current_index, #conflict_files, relative_path, status)

		vim.ui.select(options, {
			prompt = prompt,
			format_item = function(item)
				return item
			end,
		}, function(choice)
			if not choice then
				-- Cancelled - skip remaining files
				for i = current_index, #conflict_files do
					resolutions[conflict_files[i]] = "skip"
				end
				callback(resolutions)
				return
			end

			if choice:match("^Use Disk") then
				resolutions[relative_path] = "disk"
				current_index = current_index + 1
				show_next_conflict()
			elseif choice:match("^Use Stashed") then
				resolutions[relative_path] = "stashed"
				current_index = current_index + 1
				show_next_conflict()
			elseif choice:match("^Skip") then
				-- Skip remaining files
				for i = current_index, #conflict_files do
					resolutions[conflict_files[i]] = "skip"
				end
				callback(resolutions)
			end
		end)
	end

	show_next_conflict()
end

--- Simple info notification (non-blocking)
---@param title string
---@param message string
---@param timeout? number
function M.show_info(title, message, timeout)
	-- Simple info function for backward compatibility
end

return M
