local Buffer = require("harpoon.buffer")
local Logger = require("harpoon.logger")
local Extensions = require("harpoon.extensions")

---@class HarpoonToggleOptions
---@field border? any this value is directly passed to nvim_open_win
---@field title_pos? any this value is directly passed to nvim_open_win
---@field title? string this value is directly passed to nvim_open_win
---@field ui_fallback_width? number used if we can't get the current window
---@field ui_width_ratio? number this is the ratio of the editor window to use
---@field ui_max_width? number this is the max width the window can be
---@field height_in_lines? number this is the max height in lines that the window can be

---@return HarpoonToggleOptions
local function toggle_config(config)
    return vim.tbl_extend("force", {
        ui_fallback_width = 69,
        ui_width_ratio = 0.62569,
    }, config or {})
end

---@class HarpoonUI
---@field win_id number
---@field bufnr number
---@field settings HarpoonSettings
---@field active_list HarpoonList
---@field _menu_type "list"|"sub_project"|nil
---@field _sub_project_harpoon Harpoon?
---@field _sub_project_original string[]?
local HarpoonUI = {}

---@param list HarpoonList
---@return string
local function list_name(list)
    return list and list.name or "nil"
end

--- Strips the active sub-project prefix from a display line if present.
---@param line string
---@param prefix string
---@return string
local function strip_active_prefix(line, prefix)
    if vim.startswith(line, prefix) then
        return line:sub(#prefix + 1)
    end
    return line
end

HarpoonUI.__index = HarpoonUI

---@param settings HarpoonSettings
---@return HarpoonUI
function HarpoonUI:new(settings)
    return setmetatable({
        win_id = nil,
        bufnr = nil,
        active_list = nil,
        settings = settings,
        _menu_type = nil,
        _sub_project_harpoon = nil,
        _sub_project_original = nil,
    }, self)
end

function HarpoonUI:close_menu()
    if self.closing then
        return
    end

    self.closing = true
    Logger:log(
        "ui#close_menu name: ",
        list_name(self.active_list),
        "win and bufnr",
        {
            win = self.win_id,
            bufnr = self.bufnr,
        }
    )

    if self.bufnr ~= nil and vim.api.nvim_buf_is_valid(self.bufnr) then
        vim.api.nvim_buf_delete(self.bufnr, { force = true })
    end

    if self.win_id ~= nil and vim.api.nvim_win_is_valid(self.win_id) then
        vim.api.nvim_win_close(self.win_id, true)
    end

    self.active_list = nil
    self.win_id = nil
    self.bufnr = nil
    self._menu_type = nil
    self._sub_project_harpoon = nil
    self._sub_project_original = nil

    self.closing = false
end

--- TODO: Toggle_opts should be where we get extra style and border options
--- and we should create a nice minimum window
---@param toggle_opts HarpoonToggleOptions
---@param buffer_callbacks? HarpoonBufferCallbacks
---@return number,number
function HarpoonUI:_create_window(toggle_opts, buffer_callbacks)
    local win = vim.api.nvim_list_uis()

    local width = toggle_opts.ui_fallback_width

    if #win > 0 then
        -- no ackshual reason for 0.62569, just looks complicated, and i want
        -- to make my boss think i am smart
        width = math.floor(win[1].width * toggle_opts.ui_width_ratio)
    end

    if toggle_opts.ui_max_width and width > toggle_opts.ui_max_width then
        width = toggle_opts.ui_max_width
    end

    local height = toggle_opts.height_in_lines or 8 -- 8 lines is default height
    local bufnr = vim.api.nvim_create_buf(false, true)
    local win_id = vim.api.nvim_open_win(bufnr, true, {
        relative = "editor",
        title = toggle_opts.title or "Harpoon",
        title_pos = toggle_opts.title_pos or "left",
        row = math.floor(((vim.o.lines - height) / 2) - 1),
        col = math.floor((vim.o.columns - width) / 2),
        width = width,
        height = height,
        style = "minimal",
        border = toggle_opts.border or "single",
    })

    if win_id == 0 then
        Logger:log(
            "ui#_create_window failed to create window, win_id returned 0"
        )
        self.bufnr = bufnr
        self:close_menu()
        error("Failed to create window")
    end

    Buffer.setup_autocmds_and_keymaps(bufnr, buffer_callbacks)

    self.win_id = win_id
    vim.api.nvim_set_option_value("number", true, {
        win = win_id,
    })

    return win_id, bufnr
end

---@param list? HarpoonList
---TODO: @param opts? HarpoonToggleOptions
function HarpoonUI:toggle_quick_menu(list, opts)
    opts = toggle_config(opts)
    if list == nil or self.win_id ~= nil then
        Logger:log("ui#toggle_quick_menu#closing", list and list.name)
        if self.settings.save_on_toggle then
            self:save()
        end
        self:close_menu()
        return
    end

    -- grab the current file before opening the quick menu
    local current_file = vim.api.nvim_buf_get_name(0)

    Logger:log("ui#toggle_quick_menu#opening", list and list.name)
    local win_id, bufnr = self:_create_window(opts)

    self.win_id = win_id
    self.bufnr = bufnr
    self.active_list = list
    self._menu_type = "list"

    local contents = self.active_list:display()

    vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, contents)

    Extensions.extensions:emit(Extensions.event_names.UI_CREATE, {
        win_id = win_id,
        bufnr = bufnr,
        current_file = current_file,
        contents = contents,
    })
end

function HarpoonUI:_get_processed_ui_contents()
    local list = Buffer.get_contents(self.bufnr)
    local length = #list
    return list, length
end

---@param options? any
function HarpoonUI:select_menu_item(options)
    local idx = vim.fn.line(".")

    -- must first save any updates potentially made to the list before
    -- navigating
    local list, length = self:_get_processed_ui_contents()
    self.active_list:resolve_displayed(list, length)

    Logger:log(
        "ui#select_menu_item selecting item",
        idx,
        "from",
        list,
        "options",
        options
    )

    list = self.active_list
    self:close_menu()
    list:select(idx, options)
end

function HarpoonUI:save()
    local list, length = self:_get_processed_ui_contents()

    Logger:log("ui#save", list)
    self.active_list:resolve_displayed(list, length)
    if self.settings.sync_on_ui_close then
        require("harpoon"):sync()
    end
end

---@param settings HarpoonSettings
function HarpoonUI:configure(settings)
    self.settings = settings
end

--- Opens (or closes) the sub-project picker floating window.
--- Behaves like toggle_quick_menu but displays sub-project names instead of
--- file paths. The user can add/delete/rename sub-projects by editing lines,
--- and press <CR> to switch to a sub-project.
---@param harpoon_instance Harpoon | nil
---@param opts? HarpoonToggleOptions
function HarpoonUI:toggle_sub_project_menu(harpoon_instance, opts)
    opts = vim.tbl_extend("force", {
        ui_fallback_width = 69,
        ui_width_ratio = 0.62569,
    }, opts or {})
    opts.title = opts.title or "Harpoons"

    if harpoon_instance == nil or self.win_id ~= nil then
        Logger:log("ui#toggle_sub_project_menu#closing")
        if
            self.settings.save_on_toggle
            and self._menu_type == "sub_project"
        then
            self:save_sub_projects()
        end
        self:close_menu()
        return
    end

    Logger:log("ui#toggle_sub_project_menu#opening")

    -- Build callbacks for the sub-project buffer
    local sub_callbacks = {
        on_select = function()
            self:select_sub_project_item()
        end,
        on_toggle = function(key)
            Logger:log("sub_project_ui toggle by '" .. key .. "'")
            self:toggle_sub_project_menu(nil)
        end,
        on_save = function()
            self:save_sub_projects()
            vim.schedule(function()
                Logger:log("sub_project_ui toggle by BufWriteCmd")
                self:toggle_sub_project_menu(nil)
            end)
        end,
    }

    local win_id, bufnr = self:_create_window(opts, sub_callbacks)

    self.win_id = win_id
    self.bufnr = bufnr
    self._menu_type = "sub_project"
    self._sub_project_harpoon = harpoon_instance

    -- Get sub-project names in persisted display order, with <default> first
    local ordered = harpoon_instance:find_sub_projects_ordered()
    local display_name = harpoon_instance.DEFAULT_SUB_PROJECT_DISPLAY
    local prefix = harpoon_instance.ACTIVE_SUB_PROJECT_PREFIX
    local active = harpoon_instance.active_sub_project

    local projects = {}
    -- <default> is active when active_sub_project is nil
    if active == nil then
        table.insert(projects, prefix .. display_name)
    else
        table.insert(projects, display_name)
    end
    for _, name in ipairs(ordered) do
        if name == active then
            table.insert(projects, prefix .. name)
        else
            table.insert(projects, name)
        end
    end
    self._sub_project_original = vim.deepcopy(projects)

    vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, projects)

    Extensions.extensions:emit(Extensions.event_names.SUB_PROJECT_UI_CREATE, {
        win_id = win_id,
        bufnr = bufnr,
        contents = projects,
    })
end

--- Called when the user presses <CR> in the sub-project picker.
--- Switches to the sub-project under the cursor and closes the menu.
--- Selecting "<default>" switches back to the default project context.
function HarpoonUI:select_sub_project_item()
    local idx = vim.fn.line(".")
    local lines = Buffer.get_contents(self.bufnr)
    local raw = lines[idx]

    local harpoon_inst = self._sub_project_harpoon
    local prefix = harpoon_inst.ACTIVE_SUB_PROJECT_PREFIX
    local name = strip_active_prefix(raw or "", prefix)

    Logger:log("ui#select_sub_project_item", name)

    self:close_menu()

    if name ~= "" then
        local display_name = harpoon_inst.DEFAULT_SUB_PROJECT_DISPLAY
        if name == display_name then
            harpoon_inst:set_sub_project(nil)
        else
            harpoon_inst:set_sub_project(name)
        end
    end
end

--- Called when the user saves (:w) the sub-project picker buffer.
--- Reconciles the buffer contents against the original sub-project list:
--- deleted lines = delete sub-project, new lines = create sub-project.
--- The display order is persisted by resolve_sub_projects.
function HarpoonUI:save_sub_projects()
    local raw_lines = Buffer.get_contents(self.bufnr)

    local harpoon_inst = self._sub_project_harpoon
    if not harpoon_inst then
        return
    end

    local prefix = harpoon_inst.ACTIVE_SUB_PROJECT_PREFIX

    -- Strip the active prefix from all lines before reconciliation
    local lines = {}
    for _, line in ipairs(raw_lines) do
        table.insert(lines, strip_active_prefix(line, prefix))
    end

    -- Also strip the prefix from the original snapshot
    local original = {}
    for _, line in ipairs(self._sub_project_original) do
        table.insert(original, strip_active_prefix(line, prefix))
    end

    Logger:log("ui#save_sub_projects", lines)

    harpoon_inst:resolve_sub_projects(lines, original)

    -- Update the original snapshot to the new state (ordered, with <default>
    -- and prefix on the active entry)
    local display_name = harpoon_inst.DEFAULT_SUB_PROJECT_DISPLAY
    local active = harpoon_inst.active_sub_project
    local ordered = harpoon_inst:find_sub_projects_ordered()
    local updated = {}
    if active == nil then
        table.insert(updated, prefix .. display_name)
    else
        table.insert(updated, display_name)
    end
    for _, name in ipairs(ordered) do
        if name == active then
            table.insert(updated, prefix .. name)
        else
            table.insert(updated, name)
        end
    end
    self._sub_project_original = updated
end

return HarpoonUI
