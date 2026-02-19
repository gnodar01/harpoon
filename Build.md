# Harpoon Sub-Projects: Build Notes

## Overview

Sub-projects allow users to maintain multiple independent sets of harpoon lists
within a single project directory. Each sub-project has its own default
`__harpoon_files` list (and any other named lists). The active sub-project
persists across Neovim sessions.

This document covers the API layer only. UI elements (picker, status line
indicator, etc.) are planned for a future phase.

---

## Architecture

### Design Decisions

1. **Single hash file per project.** The existing hashing mechanism is
   unchanged. One project directory = one `~/.local/share/nvim/harpoon/<sha256>.json`
   file. Sub-projects are stored as **sibling top-level keys** inside this file.

2. **Sub-projects are distinct from lists.** Lists categorize *types* of items
   (files, terminals). Sub-projects categorize *task contexts* (feature work,
   bug fixes). Each sub-project contains its own independent set of lists.

3. **Context switching, not namespacing.** The user switches the active
   sub-project once, and all subsequent `harpoon:list()` calls automatically
   operate on the active sub-project's data. There is no need to pass a
   sub-project name to every call.

4. **Backward compatible.** Existing data files work without any migration.
   The default project key (the absolute CWD path) continues to function
   exactly as before. Sub-projects only appear when explicitly created.

### Data Format

**Before (unchanged for existing users):**
```json
{
  "/home/user/my-project": {
    "__harpoon_files": ["..."]
  }
}
```

**After (with sub-projects):**
```json
{
  "/home/user/my-project": {
    "__harpoon_files": ["..."],
    "__harpoon_active_sub_project": "feature-branch-a"
  },
  "feature-branch-a": {
    "__harpoon_files": ["..."]
  },
  "bugfix-y": {
    "__harpoon_files": ["..."]
  }
}
```

- The **default project key** (absolute path) stores the default context's
  lists and the `__harpoon_active_sub_project` metadata field.
- **Sub-project keys** are plain string names chosen by the user. They are
  siblings at the top level.
- The `__harpoon_active_sub_project` metadata value is a string (the name of
  the active sub-project) or absent/null (meaning default context is active).

### Files Changed

| File | Change |
|------|--------|
| `lua/harpoon/data.lua` | Added `Data:keys()`, `Data:clear_key()`, `_deleted_keys` tracking, and `ACTIVE_SUB_PROJECT_KEY` constant. Updated `Data:sync()` to apply pending deletions. |
| `lua/harpoon/init.lua` | Added `active_sub_project` state, `get_current_key()` helper, sub-project API methods. Refactored `list()`, `sync()`, `_for_each_list()` to use `get_current_key()`. Added `_restore_active_sub_project()` call in `setup()`. |
| `lua/harpoon/test/sub_project_spec.lua` | New test file with 13 tests covering the sub-project API. |

---

## API Reference

### `harpoon:get_current_key()`

Returns the current data lookup key.

- If no sub-project is active: returns the project key (e.g. CWD path).
- If a sub-project is active: returns the sub-project name.

```lua
local key = harpoon:get_current_key()
-- "feature-a" or "/home/user/my-project"
```

### `harpoon:set_sub_project(name)`

Switch the active sub-project context. All subsequent `harpoon:list()` calls
will operate on the sub-project's data.

- **`name`** (`string?`): The sub-project name. Pass `nil` to return to the
  default project context.
- Syncs the current context before switching.
- Persists the choice to disk so it survives Neovim restarts.

```lua
-- Switch to a sub-project (creates it implicitly on first list access)
harpoon:set_sub_project("feature-auth")

-- Return to the default project context
harpoon:set_sub_project(nil)
```

### `harpoon:find_sub_projects()`

Returns a list of all sub-project names for the current project. Does **not**
include the default project key.

- **Returns:** `string[]`

```lua
local projects = harpoon:find_sub_projects()
-- { "feature-auth", "bugfix-123" }
```

### `harpoon:delete_sub_project(name)`

Deletes a sub-project and all of its lists from the data store.

- **`name`** (`string`): The sub-project name to delete. Cannot be empty or
  the default project key.
- If the deleted sub-project is the currently active one, automatically reverts
  to the default project context.

```lua
harpoon:delete_sub_project("feature-auth")
```

**Errors:**
- `"Harpoon: cannot delete sub-project with empty name"` if `name` is `""`.
- `"Harpoon: cannot delete the default project"` if `name` matches the project
  key.

### `harpoon:list(name)`

Unchanged API. Now context-aware: returns the list for the active sub-project
(or the default project if no sub-project is active).

```lua
-- In default context: returns default project's file list
harpoon:list()

-- Switch context, same call returns a different list
harpoon:set_sub_project("feature-x")
harpoon:list()  -- feature-x's file list
```

---

## Usage Examples

### Basic Workflow

```lua
local harpoon = require("harpoon")

-- Normal usage (no sub-projects, fully backward compatible)
harpoon:list():add()
harpoon:list():select(1)

-- Start working on a feature branch
harpoon:set_sub_project("feature-auth")
-- list() is now empty for this new sub-project
harpoon:list():add()  -- adds current file to feature-auth's list

-- Check what sub-projects exist
local projects = harpoon:find_sub_projects()
-- { "feature-auth" }

-- Switch back to main project
harpoon:set_sub_project(nil)
-- list() shows original files again

-- Clean up when done
harpoon:delete_sub_project("feature-auth")
```

### Keybinding Examples

```lua
-- Toggle sub-project (example, UI layer not yet built)
vim.keymap.set("n", "<leader>hs", function()
    vim.ui.input({ prompt = "Sub-project name (empty for default): " }, function(name)
        if name == "" then name = nil end
        require("harpoon"):set_sub_project(name)
    end)
end)

-- List sub-projects
vim.keymap.set("n", "<leader>hS", function()
    local projects = require("harpoon"):find_sub_projects()
    if #projects == 0 then
        print("No sub-projects")
        return
    end
    vim.ui.select(projects, { prompt = "Switch to sub-project:" }, function(choice)
        if choice then
            require("harpoon"):set_sub_project(choice)
        end
    end)
end)
```

---

## Backward Compatibility & Migration

### No migration required for existing users

Existing JSON data files are 100% compatible. The changes are additive:

1. **Old data files** do not have `__harpoon_active_sub_project` in their
   default key. On load, `_restore_active_sub_project()` finds no metadata and
   sets `active_sub_project = nil`. This is identical to pre-change behavior.

2. **Old data files** do not have sub-project sibling keys. `find_sub_projects()`
   returns an empty list. No sub-project features activate unless the user
   explicitly calls `set_sub_project()`.

3. The `list()`, `sync()`, and `_for_each_list()` methods were refactored to
   use `get_current_key()` instead of `self.config.settings.key()`. When no
   sub-project is active, `get_current_key()` returns the same value as
   `self.config.settings.key()`, so behavior is identical.

### Manual migration (only if needed)

If you have **manually edited** your harpoon JSON files and want to convert
existing data into a sub-project, you can do so by hand:

1. Open `~/.local/share/nvim/harpoon/<hash>.json`
2. Copy the contents of your project key into a new sibling key:

```json
{
  "/home/user/project": {
    "__harpoon_files": ["original files..."]
  },
  "my-new-subproject": {
    "__harpoon_files": ["copied or new files..."]
  }
}
```

3. Optionally set the active sub-project:

```json
{
  "/home/user/project": {
    "__harpoon_files": ["..."],
    "__harpoon_active_sub_project": "my-new-subproject"
  },
  "my-new-subproject": {
    "__harpoon_files": ["..."]
  }
}
```

---

## Testing

### Test File

`lua/harpoon/test/sub_project_spec.lua` contains 13 tests:

| Test | What it verifies |
|------|-----------------|
| starts with no active sub-project | Default state is nil, key is project path |
| can switch to a new sub-project | `set_sub_project` updates state and key |
| can switch back to default by passing nil | `set_sub_project(nil)` restores default |
| sub-project list is empty initially | New sub-project starts with no files |
| lists are isolated between default and sub-project | Adding files in one context doesn't affect the other |
| lists are isolated between two sub-projects | Two sub-projects maintain independent lists |
| find_sub_projects returns sub-project names | Correctly enumerates created sub-projects |
| delete_sub_project removes the sub-project data | Data is removed from memory and disk |
| deleting active sub-project reverts to default | Auto-fallback on deletion of active context |
| cannot delete the default project | Error guard |
| cannot delete with empty name | Error guard |
| persists active sub-project across reload | Metadata survives data reload |
| each sub-project supports its own named lists | Custom list names (not just default) are isolated |

### Running Tests

The test suite uses [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
as the test runner. Plenary must be available at `../plenary.nvim` relative to
the harpoon directory (or in your Neovim runtime path).

```bash
# Run all tests
make test

# Run only sub-project tests (with plenary in lazy.nvim path)
nvim --headless --noplugin -u scripts/tests/minimal.vim \
  -c "PlenaryBustedFile lua/harpoon/test/sub_project_spec.lua"
```

### Known Pre-existing Test Failures

On macOS, several tests in `harpoon_spec.lua`, `config_spec.lua`, and
`ui_spec.lua` fail due to `/tmp` being a symlink to `/private/tmp`. These
failures exist in the original codebase and are **not caused by the
sub-project changes**. The sub-project tests avoid this issue by comparing
stored values rather than raw `os.tmpname()` paths.

### Validating No Regressions

To confirm no regressions, run the full test suite and verify:

- `logger_spec.lua`: 3/3 pass
- `list_spec.lua`: 9/9 pass
- `harpoon_spec.lua`: 2 pass, 5 fail (pre-existing macOS symlink issue)
- `config_spec.lua`: 0 pass, 1 fail (pre-existing macOS symlink issue)
- `ui_spec.lua`: 9 pass, 2 fail (pre-existing macOS symlink issue)
- `sub_project_spec.lua`: 13/13 pass

The pass/fail counts for pre-existing tests should be identical before and
after the sub-project changes.

---

## Future Work (UI Layer)

The following UI features are **not yet implemented** and are left as
future work:

- **Sub-project picker**: A floating window or telescope extension to browse
  and switch between sub-projects.
- **Status line indicator**: Show the active sub-project name in the status
  line.
- **Sub-project creation UI**: A prompt to name a new sub-project when
  creating one.
- **Toggle menu title**: Update `ui.lua` to show the active sub-project name
  in the harpoon menu title bar.
- **Extension events**: Emit events like `SUB_PROJECT_CHANGED`,
  `SUB_PROJECT_CREATED`, `SUB_PROJECT_DELETED` for extension authors.

The API layer is designed to support all of these without further changes to
`data.lua` or the core `init.lua` logic.
