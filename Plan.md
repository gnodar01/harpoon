## Sub-Projects UI Layer Plan

### Goal

Add a floating-window sub-project picker that behaves like the existing harpoon file-list menu: the user sees one sub-project name per line, can delete lines (`dd`), add lines (`o<name>`), reorder (`ddp`), rename (edit in place), and press `<CR>` to select (which calls `set_sub_project(name)` and closes the menu). Saving (`:w`) persists changes. Dismissing without save (`q`, `<Esc>`, `<C-w>`) discards.

### Architecture Overview

There are **four** areas of work:

1. **Parameterize `buffer.lua`** so both the file-list and sub-project menus can share it.
2. **Add `HarpoonUI:toggle_sub_project_menu()`** in `ui.lua`.
3. **Add a `resolve_displayed` equivalent for sub-projects** in `init.lua` (reconcile what the user typed in the buffer back to the sub-project data).
4. **Add tests** to `test/ui_spec.lua`.

---

### Step 1: Parameterize `buffer.lua`

**Problem:** `buffer.lua` currently hardcodes three callbacks that reference `require("harpoon").ui`:
- `run_select_command()` calls `harpoon.ui:select_menu_item()`
- `run_toggle_command()` calls `harpoon.ui:toggle_quick_menu()`
- The `BufWriteCmd` autocmd calls `harpoon.ui:save()` then `harpoon.ui:toggle_quick_menu()`
- The `BufLeave` autocmd calls `harpoon.ui:toggle_quick_menu()`

**Solution:** Change `M.setup_autocmds_and_keymaps(bufnr)` to accept a second argument: a **callbacks table**.

```lua
---@class HarpoonBufferCallbacks
---@field on_select fun()          -- called on <CR>
---@field on_toggle fun(key: string) -- called on q, Esc, BufLeave
---@field on_save fun()            -- called on :w (BufWriteCmd)

function M.setup_autocmds_and_keymaps(bufnr, callbacks)
```

- The existing file-list code path will pass callbacks that point to `harpoon.ui:select_menu_item()`, `harpoon.ui:toggle_quick_menu()`, `harpoon.ui:save()` (preserving current behavior exactly).
- The sub-project menu will pass its own callbacks.
- `ui.lua:_create_window()` already calls `Buffer.setup_autocmds_and_keymaps(bufnr)` -- it will need to forward the callbacks.

**Backward compatibility:** If `callbacks` is `nil`, fall back to the current hardcoded behavior. This means any external code calling `setup_autocmds_and_keymaps(bufnr)` without the second arg still works.

---

### Step 2: Add sub-project menu to `ui.lua`

Add the following to `HarpoonUI`:

**New state:** `self.active_sub_project_menu` (boolean flag to know which menu type is open, so `close_menu` / shared logic can distinguish). Alternatively, just track `self._menu_type` as `"list"` or `"sub_project"`.

**New methods:**

#### `HarpoonUI:toggle_sub_project_menu(harpoon_instance, opts)`

- If the menu is already open, close it (with optional save-on-toggle).
- Otherwise:
  1. Call `harpoon_instance:find_sub_projects()` to get the list of names.
  2. Call `self:_create_window(opts)` with `title = "Sub-Projects"`, passing sub-project-specific callbacks.
  3. Populate the buffer with one sub-project name per line.
  4. Store state: `self._sub_project_harpoon = harpoon_instance` (needed for save/select callbacks).

Note: This method needs a reference to the `Harpoon` instance (to call `set_sub_project`, `find_sub_projects`, `delete_sub_project`). The file-list menu doesn't need this because it operates on a `HarpoonList` directly. For the sub-project menu, we pass the harpoon instance.

#### `HarpoonUI:select_sub_project_item()`

- Read the line under the cursor.
- If non-empty, call `self._sub_project_harpoon:set_sub_project(name)`.
- Close the menu.

#### `HarpoonUI:save_sub_projects()`

- Read all lines from the buffer.
- Diff against the original list:
  - **Deleted lines** = sub-projects to delete (call `delete_sub_project(name)`).
  - **New lines** = sub-projects to create (call `set_sub_project(name)` then `set_sub_project(nil)` to just initialize the key, or simply ensure the key exists in data by touching it).
  - **Reordered lines** = no-op for data (order is cosmetic in the data store; sub-projects are top-level keys in a JSON object). But we may want to track display order. See open question below.
  - **Renamed lines** = delete old, create new. (Positional matching: if line N was "foo" and is now "bar", treat as rename.)

**Refinement on reconciliation:** The file-list menu uses `HarpoonList:resolve_displayed()` which does sophisticated index-based diffing. For sub-projects, the logic is simpler because sub-project names are unique strings (not complex items with value/context). The reconciliation algorithm:

1. Get `original_names` (what was displayed when the menu opened).
2. Get `current_names` (what the buffer contains now).
3. For each name in `original_names` that is NOT in `current_names`: call `delete_sub_project(name)`.
4. For each name in `current_names` that is NOT in `original_names` and is not whitespace: ensure the sub-project key exists in data (touch it by doing `self.data:_get_data(name, "__harpoon_files")`; this creates the key).
5. Sync.

This reconciliation will live in `init.lua` as `Harpoon:resolve_sub_projects(displayed_names)` to keep the UI layer thin and testable at the API level too.

---

### Step 3: Update `_create_window` signature

Currently: `_create_window(toggle_opts)` calls `Buffer.setup_autocmds_and_keymaps(bufnr)`.

Change to: `_create_window(toggle_opts, buffer_callbacks)` and forward the callbacks:

```lua
Buffer.setup_autocmds_and_keymaps(bufnr, buffer_callbacks)
```

The existing `toggle_quick_menu` will pass file-list callbacks. The new `toggle_sub_project_menu` will pass sub-project callbacks.

---

### Step 4: Add `Harpoon:resolve_sub_projects(displayed)` to `init.lua`

This is the API-layer counterpart to `HarpoonList:resolve_displayed()`. It reconciles the user's edits in the sub-project buffer back to the data store:

```lua
---@param displayed string[]  -- lines from the sub-project buffer
function Harpoon:resolve_sub_projects(displayed)
```

Logic:
1. Get `original = self:find_sub_projects()`.
2. Build a set of `displayed` (filtering whitespace).
3. Delete sub-projects in `original` but not in `displayed`.
4. Create sub-projects in `displayed` but not in `original` (ensure the key exists).
5. Sync.

---

### Step 5: Tests in `test/ui_spec.lua`

Add a new `describe("harpoon sub-project ui", ...)` block with:

| Test | Description |
|------|-------------|
| open sub-project menu with no sub-projects | Opens empty buffer, closes cleanly |
| open sub-project menu with existing sub-projects | Buffer shows one name per line |
| delete sub-project from UI | Remove a line, save, verify `find_sub_projects()` reflects deletion |
| add sub-project from UI | Add a line, save, verify it appears in `find_sub_projects()` |
| select sub-project from UI | Press `<CR>` on a line, verify `active_sub_project` is set and menu closes |
| edit (rename) sub-project from UI | Change a line's text, save, verify old is deleted and new exists |
| toggle without save discards | Edit the buffer, close without `:w`, verify no changes |
| close with q / Esc / C-w | Verify menu closes and state is cleaned up |

---

### Step 6: Extension events (optional but low-effort)

Add to `extensions/init.lua`:
- `SUB_PROJECT_CHANGED` -- emitted by `set_sub_project()`
- `SUB_PROJECT_UI_CREATE` -- emitted when the sub-project menu opens

These are cheap to add now and give extension authors hooks for status-line indicators and other integrations.

---

### Open Question: Sub-project display order

JSON objects are unordered. `find_sub_projects()` returns keys in arbitrary order. Should we track a display order for sub-projects (e.g., store an ordered list of names in the default project key)? Or is alphabetical sorting sufficient?

My recommendation: **alphabetical sort for now**, add explicit ordering later if needed. This avoids adding more metadata to the JSON format.

---

### Summary of files to modify

| File | Changes |
|------|---------|
| `lua/harpoon/buffer.lua` | Parameterize `setup_autocmds_and_keymaps` to accept callbacks table |
| `lua/harpoon/ui.lua` | Add `toggle_sub_project_menu`, `select_sub_project_item`, `save_sub_projects`; update `_create_window` to forward callbacks |
| `lua/harpoon/init.lua` | Add `resolve_sub_projects(displayed)` |
| `lua/harpoon/extensions/init.lua` | Add `SUB_PROJECT_CHANGED` and `SUB_PROJECT_UI_CREATE` event names |
| `lua/harpoon/test/ui_spec.lua` | Add sub-project UI tests |
| `Build.md` | Update with UI layer documentation |
