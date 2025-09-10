---@class EasyProjects.State
---@field save fun(project_path: string): nil
---@field save_files fun(project_path: string): table
---@field close_old_buffers fun(buffer_ids: table): nil
local M = {}

local utils = require("easy-projects.utils")
local config = require("easy-projects.config")
local ui = require("easy-projects.ui")
local diffs = require("easy-projects.diffs")

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
  
  -- Save open files (non-modified)
  project_config.files = M.save_files(project_path)
  
  -- Save modified files as diffs (only metadata in config)
  project_config.modified_files = diffs.save_modified_as_diffs(project_path)
  
  config.write(project_path, project_config)
end

--- Get list of open files relative to project path
---@param project_path string The project directory path
---@return table files List of relative file paths
function M.save_files(project_path)
  local files = {}
  local file_buffers = utils.get_file_buffers()
  
  for _, buf in ipairs(file_buffers) do
    local bufname = vim.api.nvim_buf_get_name(buf)
    if bufname ~= "" then
      local relative_path = utils.to_relative_path(bufname, project_path)
      if relative_path then
        table.insert(files, relative_path)
      end
    end
  end
  
  return files
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
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
end

--- Restore project state from configuration
---@param project_path string The project directory path
---@return integer files_opened Number of files successfully opened
function M.restore(project_path)
  local project_config = config.read(project_path)
  
  -- Restore UI state (explorer) FIRST to avoid dialog interference
  ui.restore_explorer(project_config)
  
  -- Restore regular files
  local files_opened = ui.open_files(project_path, project_config.files or {})
  
  -- Ensure we have an editor pane
  ui.ensure_editor_pane(files_opened)
  
  -- Restore modified files from diffs with conflict resolution (deferred to avoid UI conflicts)
  vim.defer_fn(function()
    diffs.restore_from_diffs(project_path, project_config.modified_files)
  end, 200) -- 200ms delay to let UI settle
  
  return files_opened
end

return M
