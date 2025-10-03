---@class EasyProjects.Projects
---@field add fun(project_path: string): boolean
---@field add_current fun(): boolean
---@field move_to_top fun(project_path: string): nil
---@field pick fun(): nil
local M = {}

local utils = require("easy-projects.utils")
local config = require("easy-projects.config")

--- Get fuzzy finder (supports both fzf-lua and telescope)
---@return string picker_type, table picker
local function get_picker()
	local ok_fzf, fzf = pcall(require, "fzf-lua")
	if ok_fzf then
		return "fzf-lua", fzf
	end

	local ok_telescope, telescope = pcall(require, "telescope.builtin")
	if ok_telescope then
		return "telescope", telescope
	end

	error("easy-projects.nvim requires either fzf-lua or telescope")
end

--- Move project to top of the list (most recently used)
---@param project_path string The project path to move to top
function M.move_to_top(project_path)
	local projects = config.read_projects()
	local updated_projects = {}
	local expanded_path = utils.expand_path(project_path)

	-- Add the current project to the top
	table.insert(updated_projects, project_path)

	-- Add all other projects (skip duplicates)
	for _, existing_project in ipairs(projects) do
		if utils.expand_path(existing_project) ~= expanded_path then
			table.insert(updated_projects, existing_project)
		end
	end

	-- Save the updated project list
	config.write_projects({ projects = updated_projects })
end

--- Open project picker interface
function M.pick()
	local projects = config.read_projects()

	if #projects == 0 then
		return
	end

	local picker_type, picker = get_picker()

	if picker_type == "fzf-lua" then
		-- Prepare project list for fzf-lua - show folder name and path
		local project_items = {}
		for _, project_path in ipairs(projects) do
			local folder_name = utils.get_folder_name(project_path)
			table.insert(project_items, folder_name .. " → " .. project_path)
		end

		picker.fzf_exec(project_items, {
			prompt = "Projects❯ ",
			actions = {
				["default"] = function(selected)
					if selected and selected[1] then
						-- Extract project path from selection (after the arrow)
						local project_path = selected[1]:match("→%s*(.+)")
						if project_path then
							require("easy-projects").switch_to_project(project_path)
						end
					end
				end,
			},
		})
	elseif picker_type == "telescope" then
		-- Telescope implementation
		local pickers = require("telescope.pickers")
		local finders = require("telescope.finders")
		local conf = require("telescope.config").values
		local actions = require("telescope.actions")
		local action_state = require("telescope.actions.state")

		pickers
			.new({}, {
				prompt_title = "Projects",
				finder = finders.new_table({
					results = projects,
					entry_maker = function(project_path)
						local folder_name = utils.get_folder_name(project_path)
						return {
							value = project_path,
							display = folder_name .. " → " .. project_path,
							ordinal = folder_name,
						}
					end,
				}),
				sorter = conf.generic_sorter({}),
				attach_mappings = function(prompt_bufnr, map)
					actions.select_default:replace(function()
						actions.close(prompt_bufnr)
						local selection = action_state.get_selected_entry()
						require("easy-projects").switch_to_project(selection.value)
					end)
					return true
				end,
			})
			:find()
	end
end

--- Add current directory as a project
---@return boolean success True if project was added successfully
function M.add_current()
	local cwd = vim.fn.getcwd()
	return M.add(cwd)
end

--- Add project by path
---@param project_path string The project path to add
---@return boolean success True if project was added successfully
function M.add(project_path)
	local expanded_path = utils.expand_path(project_path)

	if not utils.is_directory(expanded_path) then
		return false
	end

	-- Normalize the path (resolve symlinks, remove trailing slashes, etc.)
	local normalized_path = vim.fn.fnamemodify(expanded_path, ":p:~")

	local projects = config.read_projects()

	-- Check if project already exists (compare normalized paths)
	for _, existing_project in ipairs(projects) do
		local normalized_existing = vim.fn.fnamemodify(utils.expand_path(existing_project), ":p:~")
		if normalized_existing == normalized_path then
			return false
		end
	end

	table.insert(projects, normalized_path) -- Store normalized path
	config.write_projects({ projects = projects })

	return true
end

--- Edit projects file directly
function M.edit()
	-- Ensure projects file exists
	config.read_projects()
	vim.cmd("edit " .. utils.escape_path(config.get_projects_config_path()))
end

return M
