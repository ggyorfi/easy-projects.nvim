-- Plugin entry point for easy-projects.nvim
-- This file is automatically sourced when the plugin loads

if vim.g.loaded_easy_projects then
  return
end
vim.g.loaded_easy_projects = 1

-- Custom completion function for directories
local function complete_directories(arg_lead, cmd_line, cursor_pos)
  return vim.fn.glob(arg_lead .. "*", false, true)
end

-- Create user commands
vim.api.nvim_create_user_command("EasyOpenProjects", function()
  require("easy-projects").pick_project()
end, { desc = "Open project picker" })

vim.api.nvim_create_user_command("EasyAddProject", function(opts)
  local path = opts.args ~= "" and opts.args or vim.fn.getcwd()
  require("easy-projects").add_project(path)
end, {
  desc = "Add current or specified directory as project",
  nargs = "?",
  complete = complete_directories
})

vim.api.nvim_create_user_command("EasyEditProjects", function()
  require("easy-projects").edit_projects()
end, { desc = "Edit projects file" })

-- Easy commands for common tasks
vim.api.nvim_create_user_command("EasyQuit", function()
  vim.cmd("qa!")
end, { desc = "Quit Neovim without saving" })

vim.api.nvim_create_user_command("EasyCloseAllSaved", function()
  local buffers = vim.api.nvim_list_bufs()
  for _, buf in ipairs(buffers) do
    if vim.api.nvim_buf_is_loaded(buf) and 
       vim.api.nvim_buf_is_valid(buf) and
       not vim.api.nvim_buf_get_option(buf, "modified") and
       vim.api.nvim_buf_get_option(buf, "buflisted") then
      vim.api.nvim_buf_delete(buf, {})
    end
  end
end, { desc = "Close all unmodified buffers" })

vim.api.nvim_create_user_command("EasyToggleExplorer", function()
  -- Get saved explorer width from project config
  local cwd = vim.fn.getcwd()
  local config = require("easy-projects.config").read(cwd)
  local saved_width = config.ui and config.ui.explorer_width
  
  if not _G.Snacks or not _G.Snacks.explorer then
    vim.notify("Snacks explorer not available", vim.log.levels.WARN)
    return
  end
  
  if saved_width then
    -- Open explorer with saved width
    _G.Snacks.explorer({
      layout = {
        layout = {
          width = saved_width
        }
      }
    })
  else
    -- Fallback to default
    _G.Snacks.explorer()
  end
end, { desc = "Toggle explorer with saved width" })

-- Create autocmd group for plugin events
vim.api.nvim_create_augroup("EasyProjects", { clear = true })

-- Initialize the plugin
require("easy-projects").setup()