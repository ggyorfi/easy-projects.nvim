---@class EasyProjects.Config
---@field read fun(project_path: string): table
---@field write fun(project_path: string, config: table): boolean
---@field get_projects_config_path fun(): string
local M = {}

local utils = require("easy-projects.utils")

--- Pretty print JSON with proper indentation
---@param data table The data to encode as JSON
---@return string json_str The formatted JSON string
local function encode_json_pretty(data)
	-- Simple recursive JSON pretty printer
	local function serialize(obj, indent)
		indent = indent or 0
		local indent_str = string.rep("  ", indent)
		local next_indent_str = string.rep("  ", indent + 1)

		if type(obj) == "table" then
			if next(obj) == nil then
				return "{}"
			end

			-- Check if it's an array
			local is_array = true
			local count = 0
			for k, _ in pairs(obj) do
				count = count + 1
				if type(k) ~= "number" or k ~= count then
					is_array = false
					break
				end
			end

			if is_array then
				local parts = {}
				table.insert(parts, "[")
				for i, v in ipairs(obj) do
					local serialized = serialize(v, indent + 1)
					if i == #obj then
						table.insert(parts, "\n" .. next_indent_str .. serialized .. "\n" .. indent_str)
					else
						table.insert(parts, "\n" .. next_indent_str .. serialized .. ",")
					end
				end
				table.insert(parts, "]")
				return table.concat(parts)
			else
				local parts = {}
				table.insert(parts, "{")
				local keys = {}
				for k, _ in pairs(obj) do
					table.insert(keys, k)
				end
				table.sort(keys)

				for i, k in ipairs(keys) do
					local v = obj[k]
					local serialized_value = serialize(v, indent + 1)
					local key_str = '"' .. tostring(k) .. '"'
					if i == #keys then
						table.insert(
							parts,
							"\n" .. next_indent_str .. key_str .. ": " .. serialized_value .. "\n" .. indent_str
						)
					else
						table.insert(parts, "\n" .. next_indent_str .. key_str .. ": " .. serialized_value .. ",")
					end
				end
				table.insert(parts, "}")
				return table.concat(parts)
			end
		elseif type(obj) == "string" then
			return '"' .. obj:gsub('"', '\\"') .. '"'
		elseif type(obj) == "number" or type(obj) == "boolean" then
			return tostring(obj)
		elseif obj == nil then
			return "null"
		else
			return '"' .. tostring(obj) .. '"'
		end
	end

	return serialize(data)
end

--- Get the projects configuration file path
---@return string config_path The full path to projects.json
function M.get_projects_config_path()
	return vim.fn.stdpath("config") .. "/projects.json"
end

--- Default projects structure
---@type table
local DEFAULT_PROJECTS = {
	projects = {
		-- Add your projects here - example:
		-- "~/code/website",
		-- "~/work/api",
	},
}

--- Get project easy directory path
---@param project_path string The project directory path
---@return string easy_dir The .easy directory path
local function get_easy_dir(project_path)
	return utils.expand_path(project_path) .. "/.easy"
end

--- Get project config file path (new structure)
---@param project_path string The project directory path
---@return string config_path The easy.json file path
local function get_config_path(project_path)
	return get_easy_dir(project_path) .. "/easy.json"
end

--- Get project diffs directory path
---@param project_path string The project directory path
---@return string diffs_dir The diffs directory path
function M.get_diffs_dir(project_path)
	return get_easy_dir(project_path) .. "/diffs"
end

--- Migrate old .easy.json to new .easy/easy.json structure
---@param project_path string The project directory path
---@return boolean migrated True if migration occurred
local function migrate_old_config(project_path)
	local old_config_path = utils.expand_path(project_path) .. "/.easy.json"
	if not utils.is_readable(old_config_path) then
		return false -- No old config to migrate
	end

	-- Read old config
	local file = io.open(old_config_path, "r")
	if not file then
		return false
	end
	local content = file:read("*all")
	file:close()

	-- Create new directory structure
	local easy_dir = get_easy_dir(project_path)
	vim.fn.mkdir(easy_dir, "p")
	vim.fn.mkdir(M.get_diffs_dir(project_path), "p")

	-- Write to new location
	local new_config_path = get_config_path(project_path)
	local new_file = io.open(new_config_path, "w")
	if new_file then
		new_file:write(content)
		new_file:close()

		-- Remove old config
		os.remove(old_config_path)
		return true
	end

	return false
end

--- Read project configuration from .easy/easy.json file
---@param project_path string The project directory path
---@return table config The project configuration
function M.read(project_path)
	-- Try migration first
	migrate_old_config(project_path)

	local config_path = get_config_path(project_path)
	local file = io.open(config_path, "r")
	if not file then
		return {}
	end

	local content = file:read("*all")
	file:close()

	local ok, config = pcall(vim.fn.json_decode, content)
	return ok and config or {}
end

--- Write project configuration to .easy/easy.json file
---@param project_path string The project directory path
---@param config table The configuration to write
---@return boolean success True if write was successful
function M.write(project_path, config)
	-- Ensure directory structure exists
	local easy_dir = get_easy_dir(project_path)
	vim.fn.mkdir(easy_dir, "p")
	vim.fn.mkdir(M.get_diffs_dir(project_path), "p")

	local config_path = get_config_path(project_path)
	local file = io.open(config_path, "w")
	if not file then
		return false
	end

	local json_str = encode_json_pretty(config)
	file:write(json_str)
	file:close()
	return true
end

--- Read projects list from global configuration
---@return table projects List of project paths
function M.read_projects()
	local config_path = M.get_projects_config_path()
	local file = io.open(config_path, "r")
	if not file then
		-- Create default config if it doesn't exist
		M.write_projects(DEFAULT_PROJECTS)
		return DEFAULT_PROJECTS.projects
	end

	local content = file:read("*all")
	file:close()

	local ok, projects_data = pcall(vim.fn.json_decode, content)
	if ok and projects_data.projects then
		return projects_data.projects
	else
		return DEFAULT_PROJECTS.projects
	end
end

--- Write projects list to global configuration
---@param data table The projects data structure
---@return boolean success True if write was successful
function M.write_projects(data)
	local config_path = M.get_projects_config_path()
	local file = io.open(config_path, "w")
	if not file then
		return false
	end

	local json_str = encode_json_pretty(data)
	file:write(json_str)
	file:close()
	return true
end

--- Check if a directory is a tracked project
---@param project_path string The directory path to check
---@return boolean is_tracked True if directory is in the projects list
function M.is_tracked_project(project_path)
	local projects = M.read_projects()
	local expanded_path = require("easy-projects.utils").expand_path(project_path)

	for _, existing_project in ipairs(projects) do
		if require("easy-projects.utils").expand_path(existing_project) == expanded_path then
			return true
		end
	end

	return false
end

return M
