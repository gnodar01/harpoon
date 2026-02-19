local Log = require("harpoon.logger")
local Ui = require("harpoon.ui")
local Data = require("harpoon.data")
local Config = require("harpoon.config")
local List = require("harpoon.list")
local Extensions = require("harpoon.extensions")
local HarpoonGroup = require("harpoon.autocmd")

---@class Harpoon
---@field config HarpoonConfig
---@field ui HarpoonUI
---@field _extensions HarpoonExtensions
---@field data HarpoonData
---@field logger HarpoonLog
---@field lists {[string]: {[string]: HarpoonList}}
---@field hooks_setup boolean
---@field active_sub_project string?
local Harpoon = {}

Harpoon.__index = Harpoon

---@param harpoon Harpoon
local function sync_on_change(harpoon)
    local function sync(_)
        return function()
            harpoon:sync()
        end
    end

    Extensions.extensions:add_listener({
        ADD = sync("ADD"),
        REMOVE = sync("REMOVE"),
        REORDER = sync("REORDER"),
        LIST_CHANGE = sync("LIST_CHANGE"),
        POSITION_UPDATED = sync("POSITION_UPDATED"),
    })
end

---@return Harpoon
function Harpoon:new()
    local config = Config.get_default_config()

    local harpoon = setmetatable({
        config = config,
        data = Data.Data:new(config),
        logger = Log,
        ui = Ui:new(config.settings),
        _extensions = Extensions.extensions,
        lists = {},
        hooks_setup = false,
        active_sub_project = nil,
    }, self)
    sync_on_change(harpoon)

    return harpoon
end

--- Returns the current data lookup key, scoped by sub-project if one is active.
--- When no sub-project is active, returns the project key (e.g. CWD).
--- When a sub-project is active, returns the sub-project name.
---@return string
function Harpoon:get_current_key()
    if self.active_sub_project then
        return self.active_sub_project
    end
    return self.config.settings.key()
end

---@param name string?
---@return HarpoonList
function Harpoon:list(name)
    name = name or Config.DEFAULT_LIST

    local key = self:get_current_key()
    local lists = self.lists[key]

    if not lists then
        lists = {}
        self.lists[key] = lists
    end

    local existing_list = lists[name]

    if existing_list then
        self._extensions:emit(Extensions.event_names.LIST_READ, existing_list)
        return existing_list
    end

    local data = self.data:data(key, name)
    local list_config = Config.get_config(self.config, name)

    local list = List.decode(list_config, name, data)
    self._extensions:emit(Extensions.event_names.LIST_CREATED, list)
    lists[name] = list

    return list
end

---@param cb fun(list: HarpoonList, config: HarpoonPartialConfigItem, name: string)
function Harpoon:_for_each_list(cb)
    local key = self:get_current_key()
    local lists = self.lists[key]
    if not lists then
        return
    end

    for name, list in pairs(lists) do
        local list_config = Config.get_config(self.config, name)
        cb(list, list_config, name)
    end
end

function Harpoon:sync()
    local key = self:get_current_key()
    self:_for_each_list(function(list, _, list_name)
        if list.config.encode == false then
            return
        end

        local encoded = list:encode()
        self.data:update(key, list_name, encoded)
    end)
    self.data:sync()
end

--luacheck: ignore 212/self
function Harpoon:info()
    return {
        paths = Data.info(),
        default_list_name = Config.DEFAULT_LIST,
    }
end

--- PLEASE DONT USE THIS OR YOU WILL BE FIRED
function Harpoon:dump()
    return self.data._data
end

---@param extension HarpoonExtension
function Harpoon:extend(extension)
    self._extensions:add_listener(extension)
end

function Harpoon:__debug_reset()
    require("plenary.reload").reload_module("harpoon")
end

--- Persists the active sub-project name into the default project key's metadata.
--- When name is nil, removes the metadata entry (returning to default).
---@param name string?
function Harpoon:_save_active_sub_project(name)
    local default_key = self.config.settings.key()
    if name then
        self.data:update(default_key, Data.ACTIVE_SUB_PROJECT_KEY, name)
    else
        -- Clear the metadata entry
        local raw = self.data:data(default_key, Data.ACTIVE_SUB_PROJECT_KEY)
        if raw and raw ~= "" then
            self.data:update(default_key, Data.ACTIVE_SUB_PROJECT_KEY, vim.NIL)
        end
    end
    self.data:sync()
end

--- Restores the active sub-project from persisted metadata.
--- Called during setup() to resume the last session's context.
function Harpoon:_restore_active_sub_project()
    local default_key = self.config.settings.key()
    local stored = self.data:data(default_key, Data.ACTIVE_SUB_PROJECT_KEY)
    if stored and type(stored) == "string" and stored ~= "" then
        self.active_sub_project = stored
        Log:log("sub_project#restore", "restored active sub-project:", stored)
    else
        self.active_sub_project = nil
    end
end

--- Switch the active sub-project context. All subsequent list() calls will
--- operate on the sub-project's data. Pass nil to return to the default
--- project context.
---@param name string?
function Harpoon:set_sub_project(name)
    -- Sync current context before switching
    self:sync()

    self.active_sub_project = name
    self:_save_active_sub_project(name)

    self._extensions:emit(Extensions.event_names.SUB_PROJECT_CHANGED, {
        name = name,
    })

    Log:log("sub_project#set", "switched to:", name or "<default>")
end

--- Returns a list of all sub-project names for the current project.
--- Does not include the default project key.
---@return string[]
function Harpoon:find_sub_projects()
    local default_key = self.config.settings.key()
    local all_keys = self.data:keys()
    local sub_projects = {}

    for _, key in ipairs(all_keys) do
        if key ~= default_key then
            table.insert(sub_projects, key)
        end
    end

    return sub_projects
end

--- Deletes a sub-project and all of its lists from the data store.
--- If the deleted sub-project is the currently active one, reverts to
--- the default project context.
---@param name string
function Harpoon:delete_sub_project(name)
    if not name or name == "" then
        error("Harpoon: cannot delete sub-project with empty name")
    end

    local default_key = self.config.settings.key()
    if name == default_key then
        error("Harpoon: cannot delete the default project")
    end

    -- Clear in-memory list cache for this sub-project
    self.lists[name] = nil

    -- Clear from data store and persist
    self.data:clear_key(name)
    self.data:sync()

    -- If we just deleted the active sub-project, revert to default
    if self.active_sub_project == name then
        self.active_sub_project = nil
        self:_save_active_sub_project(nil)
    end

    Log:log("sub_project#delete", "deleted sub-project:", name)
end

--- Reconciles the user's edits in the sub-project picker buffer back to the
--- data store. This is the sub-project equivalent of HarpoonList:resolve_displayed().
---
--- For each name in original that is NOT in displayed: delete the sub-project.
--- For each name in displayed that is NOT in original: create the sub-project
--- (ensure its key exists in the data store).
---@param displayed string[]   lines from the sub-project buffer
---@param original string[]    the sub-project names when the menu was opened
function Harpoon:resolve_sub_projects(displayed, original)
    local utils = require("harpoon.utils")

    -- Build lookup sets
    local displayed_set = {}
    local displayed_clean = {}
    for _, name in ipairs(displayed) do
        if not utils.is_white_space(name) then
            displayed_set[name] = true
            table.insert(displayed_clean, name)
        end
    end

    local original_set = {}
    for _, name in ipairs(original) do
        original_set[name] = true
    end

    -- Delete sub-projects that were removed from the buffer
    for _, name in ipairs(original) do
        if not displayed_set[name] then
            -- Use pcall because delete_sub_project guards against deleting default
            pcall(function()
                self:delete_sub_project(name)
            end)
        end
    end

    -- Create sub-projects that were added in the buffer
    for _, name in ipairs(displayed_clean) do
        if not original_set[name] then
            -- Touch the key in the data store to create it
            self.data:data(name, Config.DEFAULT_LIST)
            self.data:sync()
            Log:log("sub_project#create_from_ui", "created:", name)
        end
    end
end

local the_harpoon = Harpoon:new()

---@param self Harpoon
---@param partial_config HarpoonPartialConfig?
---@return Harpoon
function Harpoon.setup(self, partial_config)
    if self ~= the_harpoon then
        ---@diagnostic disable-next-line: cast-local-type
        partial_config = self
        self = the_harpoon
    end

    ---@diagnostic disable-next-line: param-type-mismatch
    self.config = Config.merge_config(partial_config, self.config)
    self.data = Data.Data:new(self.config)
    self.ui:configure(self.config.settings)
    self._extensions:emit(Extensions.event_names.SETUP_CALLED, self.config)

    -- Restore the active sub-project from the persisted data
    self:_restore_active_sub_project()

    ---TODO: should we go through every seen list and update its config?

    if self.hooks_setup == false then
        vim.api.nvim_create_autocmd({ "BufLeave", "VimLeavePre" }, {
            group = HarpoonGroup,
            pattern = "*",
            callback = function(ev)
                self:_for_each_list(function(list, config)
                    local fn = config[ev.event]
                    if fn ~= nil then
                        fn(ev, list)
                    end

                    if ev.event == "VimLeavePre" then
                        self:sync()
                    end
                end)
            end,
        })

        self.hooks_setup = true
    end

    return self
end

return the_harpoon
