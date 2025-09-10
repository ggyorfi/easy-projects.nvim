---@class EasyProjects
---@field switch_to_project fun(project_path: string): nil
---@field pick_project fun(): nil
---@field add_current_project fun(): nil
---@field add_project fun(project_path: string): nil
---@field edit_projects fun(): nil
---@field setup fun(opts?: table): nil
local M = {}

-- Import modules
local utils = require("easy-projects.utils")
local config = require("easy-projects.config") 
local state = require("easy-projects.state")
local ui = require("easy-projects.ui")
local projects = require("easy-projects.projects")
local autocmds = require("easy-projects.autocmds")

--- Switch to a project directory and restore its state
---@param project_path string The project path to switch to
function M.switch_to_project(project_path)
  local expanded_path = utils.expand_path(project_path)
  if not utils.is_directory(expanded_path) then
    return
  end
  
  -- Check if we're already in the target project
  local current_cwd = vim.fn.getcwd()
  if current_cwd == expanded_path then
    -- Already in the target project, just set as loaded and move to top
    autocmds.set_loaded_project(expanded_path)
    projects.move_to_top(project_path)
    return
  end
  
  -- Disable autocmds during project switching to avoid interference
  autocmds.disable_tracking()
  
  -- Save current project state BEFORE switching (inside disabled autocmds)
  local current_loaded_project = autocmds.get_loaded_project()
  if current_loaded_project then
    state.save(current_loaded_project)
  end
  
  -- Get list of old project buffers to close later
  local old_buffers = state.get_old_buffers()
  
  -- Switch to new project directory FIRST
  vim.cmd("cd " .. utils.escape_path(expanded_path))
  
  -- Then restore new project's state
  local files_opened = state.restore(expanded_path)
  
  -- Move this project to the top of the list (most recently used)
  projects.move_to_top(project_path)
  
  -- Close old project buffers (still inside disabled autocmds)
  state.close_old_buffers(old_buffers)
  
  -- Set the new project as loaded
  autocmds.set_loaded_project(expanded_path)
  
  -- Re-enable autocmds
  autocmds.enable_tracking()
  
  -- Trigger User event for other plugins to react
  vim.api.nvim_exec_autocmds("User", { pattern = "LazyProjectChanged" })
end

--- Open project picker
function M.pick_project()
  projects.pick()
end

--- Add current directory as project
function M.add_current_project()
  projects.add_current()
end

--- Add project by path
---@param project_path string The project path to add
function M.add_project(project_path)
  projects.add(project_path)
end

--- Edit projects file directly
function M.edit_projects()
  projects.edit()
end

--- Setup function for configuration
---@param opts? table Optional configuration options
function M.setup(opts)
  opts = opts or {}
  
  -- Override default config path if provided
  if opts.config_file then
    -- This would need to be implemented in config module
    -- config.set_projects_config_path(vim.fn.expand(opts.config_file))
  end
  
  -- Setup keymaps if provided
  if opts.keymaps then
    for key, action in pairs(opts.keymaps) do
      vim.keymap.set("n", key, function()
        M[action]()
      end, { desc = "Easy Projects: " .. action })
    end
  end
  
  -- Setup autocmds
  autocmds.setup()
end

return M
