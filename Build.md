# Harpoon Sub-Projects: Build Notes

## Overview

Sub-projects allow users to maintain multiple independent sets of harpoon lists
within a single project directory. Each sub-project has its own default
`__harpoon_files` list (and any other named lists). The active sub-project
persists across Neovim sessions.

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
    "__harpoon_active_sub_project": "feature-branch-a",
    "__harpoon_sub_project_order": ["feature-branch-a", "bugfix-y"]
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
  lists and two metadata fields:
  - `__harpoon_active_sub_project`: a string (the name of the active
    sub-project) or absent/null (meaning default context is active).
  - `__harpoon_sub_project_order`: an ordered JSON array of sub-project names,
    representing the user's chosen display order in the picker menu.
- **Sub-project keys** are plain string names chosen by the user. They are
  siblings at the top level.
- The sub-project picker UI always shows `"<default>"` as the first entry.
  This is a display-only name; the actual data key remains the absolute path.

### Files Changed

| File | Change |
|------|--------|
| `lua/harpoon/data.lua` | Added `Data:keys()`, `Data:clear_key()`, `_deleted_keys` tracking, and `ACTIVE_SUB_PROJECT_KEY` constant. Updated `Data:sync()` to apply pending deletions. |
| `lua/harpoon/init.lua` | Added `active_sub_project` state, `get_current_key()` helper, sub-project API methods, `resolve_sub_projects()`. Refactored `list()`, `sync()`, `_for_each_list()` to use `get_current_key()`. Added `_restore_active_sub_project()` call in `setup()`. |
| `lua/harpoon/buffer.lua` | Parameterized `setup_autocmds_and_keymaps()` to accept a `HarpoonBufferCallbacks` table. Added `default_callbacks()` factory. Falls back to original behavior when no callbacks provided. |
| `lua/harpoon/ui.lua` | Added `_menu_type`, `_sub_project_harpoon`, `_sub_project_original` state fields. Added `toggle_sub_project_menu()`, `select_sub_project_item()`, `save_sub_projects()` methods. Updated `_create_window()` to forward callbacks. Updated `close_menu()` to clear sub-project state. |
| `lua/harpoon/extensions/init.lua` | Added `SUB_PROJECT_CHANGED` and `SUB_PROJECT_UI_CREATE` event names. |
| `lua/harpoon/test/sub_project_spec.lua` | 13 API-layer tests. |
| `lua/harpoon/test/ui_spec.lua` | 8 new sub-project UI tests added to the existing file. |

---

## API Reference

### Core Sub-Project API

#### `harpoon:get_current_key()`

Returns the current data lookup key.

- If no sub-project is active: returns the project key (e.g. CWD path).
- If a sub-project is active: returns the sub-project name.

```lua
local key = harpoon:get_current_key()
-- "feature-a" or "/home/user/my-project"
```

#### `harpoon:set_sub_project(name)`

Switch the active sub-project context. All subsequent `harpoon:list()` calls
will operate on the sub-project's data.

- **`name`** (`string?`): The sub-project name. Pass `nil` to return to the
  default project context.
- Syncs the current context before switching.
- Persists the choice to disk so it survives Neovim restarts.
- Emits `SUB_PROJECT_CHANGED` extension event.

```lua
harpoon:set_sub_project("feature-auth")
harpoon:set_sub_project(nil)  -- back to default
```

#### `harpoon:find_sub_projects()`

Returns a list of all sub-project names for the current project (unordered).

- **Returns:** `string[]`

```lua
local projects = harpoon:find_sub_projects()
-- { "feature-auth", "bugfix-123" }
```

#### `harpoon:find_sub_projects_ordered()`

Returns sub-project names in their persisted display order. Any sub-projects
that exist in the data but are missing from the stored order are appended
at the end.

- **Returns:** `string[]`

```lua
local ordered = harpoon:find_sub_projects_ordered()
-- { "bugfix-123", "feature-auth" }  -- in the order the user arranged them
```

#### `harpoon.DEFAULT_SUB_PROJECT_DISPLAY`

The display name used to represent the default project in the sub-project
picker menu. Value: `"<default>"`.

```lua
local name = harpoon.DEFAULT_SUB_PROJECT_DISPLAY
-- "<default>"
```

#### `harpoon.ACTIVE_SUB_PROJECT_PREFIX`

The prefix prepended to the active sub-project's line in the picker menu.
Value: `"> "`. Change this constant to customize the indicator.

```lua
local pfx = harpoon.ACTIVE_SUB_PROJECT_PREFIX
-- "> "
```

#### `harpoon:delete_sub_project(name)`

Deletes a sub-project and all of its lists from the data store.

- If the deleted sub-project is currently active, automatically reverts
  to the default project context.

```lua
harpoon:delete_sub_project("feature-auth")
```

#### `harpoon:resolve_sub_projects(displayed, original)`

Reconciles user edits from the sub-project picker buffer. Used internally
by the UI layer.

- **`displayed`** (`string[]`): Current buffer lines.
- **`original`** (`string[]`): The sub-project names when the menu opened.
- Deletes sub-projects in `original` not in `displayed`.
- Creates sub-projects in `displayed` not in `original`.

### UI API

#### `harpoon.ui:toggle_sub_project_menu(harpoon_instance, opts)`

Opens (or closes) the sub-project picker floating window. Behaves like
`toggle_quick_menu` but displays sub-project names instead of file paths.

- **`harpoon_instance`** (`Harpoon`): The harpoon instance. Pass `nil` to
  close an already-open menu.
- **`opts`** (`HarpoonToggleOptions?`): Same options as `toggle_quick_menu`.
  Defaults title to `"Sub-Projects"`.

The menu always shows `"<default>"` as the first line. Sub-projects follow
in their persisted display order (edit order is preserved across sessions).
The currently active sub-project (or `"<default>"` if none) is prefixed
with `"> "` to indicate which context is active. The prefix is defined by
`harpoon.ACTIVE_SUB_PROJECT_PREFIX` and can be customized.

The user can:
- **Delete** sub-projects by deleting lines (`dd`). Deleting `"<default>"` is
  a no-op (the default project cannot be deleted).
- **Add** sub-projects by typing new names on new lines (`o<name>`).
- **Rename** sub-projects by editing a line in place.
- **Reorder** sub-projects by moving lines (`ddp`, etc.). The order is
  persisted on save.
- **Select** a sub-project by pressing `<CR>` (switches context and closes).
  Selecting `"<default>"` switches back to the default project context.
- **Save** with `:w` (persists changes and closes).
- **Dismiss** with `q`, `<Esc>`, `<C-w>` (discards changes).

```lua
-- Open the sub-project picker
harpoon.ui:toggle_sub_project_menu(harpoon)

-- Close (or toggle)
harpoon.ui:toggle_sub_project_menu(nil)
```

#### `harpoon.ui:select_sub_project_item()`

Called internally when `<CR>` is pressed in the sub-project picker. Reads the
line under the cursor and calls `set_sub_project(name)`.

#### `harpoon.ui:save_sub_projects()`

Called internally when `:w` is pressed in the sub-project picker. Reads all
buffer lines and calls `resolve_sub_projects()` to reconcile changes.

### Buffer Callbacks API

#### `HarpoonBufferCallbacks`

```lua
---@class HarpoonBufferCallbacks
---@field on_select fun()            -- called on <CR>
---@field on_toggle fun(key: string) -- called on q, Esc, BufLeave
---@field on_save fun()              -- called on :w (BufWriteCmd)
```

`buffer.lua:setup_autocmds_and_keymaps(bufnr, callbacks)` now accepts an
optional second argument. If `nil`, uses `Buffer.default_callbacks()` which
preserves the original file-list behavior.

### Extension Events

| Event | Emitted by | Payload |
|-------|-----------|---------|
| `SUB_PROJECT_CHANGED` | `set_sub_project()` | `{ name = string? }` |
| `SUB_PROJECT_UI_CREATE` | `toggle_sub_project_menu()` | `{ win_id, bufnr, contents }` |

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
harpoon:list():add()

-- Open the sub-project picker UI
harpoon.ui:toggle_sub_project_menu(harpoon)

-- Check what sub-projects exist
local projects = harpoon:find_sub_projects()

-- Switch back to main project
harpoon:set_sub_project(nil)

-- Clean up when done
harpoon:delete_sub_project("feature-auth")
```

### Keybinding Examples

```lua
-- Toggle sub-project picker
vim.keymap.set("n", "<leader>hs", function()
    local harpoon = require("harpoon")
    harpoon.ui:toggle_sub_project_menu(harpoon)
end)

-- Quick switch back to default
vim.keymap.set("n", "<leader>hd", function()
    require("harpoon"):set_sub_project(nil)
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

4. `buffer.lua:setup_autocmds_and_keymaps()` falls back to `default_callbacks()`
   when called without a second argument. External code is unaffected.

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

### Test Files

**`lua/harpoon/test/sub_project_spec.lua`** -- 13 API-layer tests:

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

**`lua/harpoon/test/ui_spec.lua`** -- 13 sub-project UI tests added:

| Test | What it verifies |
|------|-----------------|
| open sub-project menu with no sub-projects shows `<default>` | Buffer contains only `<default>`, closes cleanly |
| open sub-project menu with existing sub-projects | `<default>` first, then sub-projects |
| delete sub-project from UI (keeping `<default>`) | Remove a sub-project line, save, verify deletion |
| add sub-project from UI | Add a line after `<default>`, save, verify creation |
| select `<default>` from UI switches to default context | `<CR>` on `<default>` calls `set_sub_project(nil)` |
| active sub-project is prefixed in the menu | Active entry shown with `"> "` prefix, others without |
| select prefixed sub-project from UI switches context | `<CR>` on prefixed line strips prefix and switches |
| select unprefixed sub-project from UI switches context | `<CR>` on unprefixed line switches normally |
| edit (rename) sub-project from UI | Change a line, save, verify old deleted and new created |
| toggle without save discards changes | Edit buffer, close without `:w`, verify no changes |
| close sub-project menu with q | Menu closes and state is cleaned up |
| sub-project display order is preserved across menu reopens | Set order, save, reopen, verify same order |
| deleting `<default>` from buffer does not delete the default project | Remove `<default>` line, save, default context still works |

### Running Tests

```bash
# Run all tests
make test

# Run specific test files (with plenary in lazy.nvim path)
nvim --headless --noplugin -u scripts/tests/minimal.vim \
  -c "PlenaryBustedFile lua/harpoon/test/sub_project_spec.lua"

nvim --headless --noplugin -u scripts/tests/minimal.vim \
  -c "PlenaryBustedFile lua/harpoon/test/ui_spec.lua"
```

### Validating No Regressions

To confirm no regressions, run the full test suite and verify:

- `logger_spec.lua`: 3/3 pass
- `list_spec.lua`: 9/9 pass
- `harpoon_spec.lua`: 2 pass, 5 fail (pre-existing macOS symlink issue)
- `config_spec.lua`: 0 pass, 1 fail (pre-existing macOS symlink issue)
- `ui_spec.lua`: 22 pass, 2 fail (pre-existing macOS symlink issue)
- `sub_project_spec.lua`: 13/13 pass

The pass/fail counts for pre-existing tests should be identical before and
after all sub-project changes.

### Known Pre-existing Test Failures

On macOS, several tests fail due to `/tmp` being a symlink to `/private/tmp`.
These failures exist in the original codebase and are **not caused by the
sub-project changes**.
