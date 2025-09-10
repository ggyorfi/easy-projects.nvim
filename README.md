# easy-projects.nvim

**Smart project management for Neovim with state persistence**

A sophisticated yet simple project manager that remembers your workspace state - open files, modified buffers, and UI layout - across project switches.

## Features

- **Manual project curation** - Only projects you explicitly add
- **State persistence** - Remembers open files, modifications, and UI layout
- **Smart conflict resolution** - Handles file conflicts when switching projects  
- **Fuzzy search** - Powered by fzf-lua integration
- **Lightweight & fast** - Efficient diff-based state management
- **Modern UI** - Clean dialogs using Snacks.nvim
- **Zero configuration** - Works out of the box

## Installation

### With [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "yourusername/easy-projects.nvim",
  dependencies = {
    "ibhagwan/fzf-lua", -- Required for project picker
  },
  lazy = false, -- Load immediately so commands are available
  keys = {
    { "<leader>fp", function() require("easy-projects").pick_project() end, desc = "Find Project" },
    { "<leader>pa", function() require("easy-projects").add_current_project() end, desc = "Add Current as Project" },
    -- Easy command keybindings
    { "<leader>qq", "<cmd>EasyQuit<cr>", desc = "Quit Neovim" },
    { "<leader>qc", "<cmd>EasyCloseAllSaved<cr>", desc = "Close All Saved Buffers" },
    { "<leader>qa", "<cmd>EasyAddProject<cr>", desc = "Add Current Project" },
  },
  opts = {}, -- Use default configuration
}
```

## Quick Start

1. **Add your first project**:
   ```
   cd ~/my-awesome-project
   <leader>pa
   ```

2. **Switch between projects**:
   ```
   <leader>fp
   ```

3. **Your state is automatically saved** - open files, modifications, explorer state, everything!

## Core Concepts

### State Persistence
Each project remembers:
- **Open files** - All buffers you had open
- **Modified files** - Unsaved changes (stored as diffs)  
- **Explorer state** - Whether sidebar was open and its width
- **UI layout** - Window arrangement

### Smart Conflict Resolution
When switching projects, if files were modified on disk since you last worked on them:
- **Batch resolution** - Handle all conflicts at once
- **Individual review** - Go through files one by one  
- **Safe choices** - Keep disk version, restore your changes, or skip

### Zero-Config Philosophy
- No session files cluttering your projects
- No complex configuration needed
- Works with any project structure
- Integrates seamlessly with existing workflows

## Configuration

```lua
{
  "yourusername/easy-projects.nvim",
  opts = {
    -- All options are optional - plugin works with defaults
    
    -- Custom projects file location
    projects_file = "~/.config/nvim/my-projects.json",
    
    -- Custom keymaps
    keymaps = {
      pick_project = "<leader>fp",
      add_project = "<leader>pa",
    },
  },
}
```

## Usage

### Managing Projects

| Command | Description |
|---------|-------------|
| `:AddProject <path>` | Add project by path |
| `<leader>pa` | Add current directory |
| `<leader>fp` | Open project picker |

### Project Switching Flow

1. **Automatic state save** - Current project state is saved
2. **Directory switch** - Changes to new project directory  
3. **State restoration** - Restores files, modifications, and UI
4. **Conflict handling** - Resolves any file conflicts intelligently

### File Conflict Resolution

When files have conflicts, you'll see a clean dialog:

```
3 files have conflicts. Choose action:

> Use Disk versions (lose stashed changes)
  Use Stashed versions (restore modified files)  
  Review each file individually
```

**Options:**
- **Disk versions** - Keep current file state, lose your modifications
- **Stashed versions** - Restore your modifications, overwrite disk changes
- **Review each** - Decide per file individually

## Requirements

- **Neovim >= 0.8**
- **fzf-lua** - For project picker interface
- **snacks.nvim** (optional) - Enhanced UI dialogs (auto-detected)

## Architecture

```
easy-projects.nvim/
├── lua/easy-projects/
│   ├── init.lua          # Main plugin interface
│   ├── projects.lua      # Project list management  
│   ├── state.lua         # State save/restore orchestration
│   ├── diffs.lua         # Diff-based file state management
│   ├── dialogs.lua       # Conflict resolution UI
│   ├── config.lua        # Configuration management
│   ├── ui.lua           # UI state management
│   ├── utils.lua        # Utility functions
│   └── autocmds.lua     # Auto-save functionality
└── plugin/
    └── lazy-project.lua  # Vim commands registration
```

## Why easy-projects?

**Other project managers:**
- Auto-detect every `.git` folder (spam!)
- Session files that break or conflict
- Heavy, complex, hard to debug
- Lose your work when switching projects

**easy-projects.nvim:**
- **You control** what counts as a project
- **Never lose work** - modifications are preserved as diffs
- **Fast & reliable** - Simple architecture, battle-tested
- **Conflict resolution** - Handles edge cases gracefully
- **Modern UX** - Clean, intuitive dialogs

## Troubleshooting

### "No projects configured"
Add your first project with `<leader>pa` or `:AddProject <path>`

### State not restoring
Check if `.easy/` directory exists in your project root. The plugin creates this automatically.

### Conflicts every time
Your files might be changing outside Neovim. Use "Review each file" to understand what's happening.

## Contributing

Contributions welcome! This plugin is built to be simple and reliable.

**Areas for contribution:**
- Additional conflict resolution strategies
- Integration with other fuzzy finders
- Performance optimizations
- Documentation improvements

## License

MIT License - See LICENSE file for details

## Acknowledgments

Built with frustration over existing project managers and a desire for something that **actually works reliably** in daily development workflow.

**Key inspirations:**
- The reliability of `cd` command
- Git's diff/patch system for state management  
- Modern Neovim's plugin ecosystem (lazy.nvim, fzf-lua, snacks.nvim)