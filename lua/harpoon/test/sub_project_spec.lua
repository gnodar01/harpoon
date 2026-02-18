local utils = require("harpoon.test.utils")
local logger = require("harpoon.logger")

---@type Harpoon
local harpoon = require("harpoon")

local Config = require("harpoon.config")
local Data = require("harpoon.data")

local eq = assert.are.same
local be = utils.before_each(os.tmpname())

describe("harpoon sub-projects", function()
    before_each(function()
        be()
        logger:clear()
        harpoon = require("harpoon")
    end)

    it("starts with no active sub-project (default context)", function()
        eq(nil, harpoon.active_sub_project)
        eq("testies", harpoon:get_current_key())
    end)

    it("can switch to a new sub-project", function()
        harpoon:set_sub_project("feature-a")

        eq("feature-a", harpoon.active_sub_project)
        eq("feature-a", harpoon:get_current_key())
    end)

    it("can switch back to default by passing nil", function()
        harpoon:set_sub_project("feature-a")
        eq("feature-a", harpoon:get_current_key())

        harpoon:set_sub_project(nil)
        eq(nil, harpoon.active_sub_project)
        eq("testies", harpoon:get_current_key())
    end)

    it("sub-project list is empty initially", function()
        harpoon:set_sub_project("feature-a")
        local list = harpoon:list()
        eq(0, list:length())
    end)

    it("lists are isolated between default and sub-project", function()
        -- Add a file in the default context
        local file_name_1 = os.tmpname()
        utils.create_file(file_name_1, { "default content" }, 1, 0)
        harpoon:list():add()
        eq(1, harpoon:list():length())

        -- Capture the value harpoon actually stored (may resolve symlinks)
        local stored_default_value = harpoon:list():get(1).value

        -- Switch to sub-project: list should be empty
        harpoon:set_sub_project("feature-a")
        eq(0, harpoon:list():length())

        -- Add a different file in sub-project
        local file_name_2 = os.tmpname()
        utils.create_file(file_name_2, { "feature content" }, 1, 0)
        harpoon:list():add()
        eq(1, harpoon:list():length())
        local stored_feature_value = harpoon:list():get(1).value

        -- The two values should be different files
        assert.are_not.equal(stored_default_value, stored_feature_value)

        -- Switch back to default: original file should still be there
        harpoon:set_sub_project(nil)
        eq(1, harpoon:list():length())
        eq(stored_default_value, harpoon:list():get(1).value)
    end)

    it("lists are isolated between two sub-projects", function()
        local file_a = os.tmpname()
        local file_b = os.tmpname()

        -- Add to sub-project A
        harpoon:set_sub_project("project-a")
        utils.create_file(file_a, { "a content" }, 1, 0)
        harpoon:list():add()
        local stored_a = harpoon:list():get(1).value

        -- Add to sub-project B
        harpoon:set_sub_project("project-b")
        utils.create_file(file_b, { "b content" }, 1, 0)
        harpoon:list():add()
        local stored_b = harpoon:list():get(1).value

        -- The two should be different files
        assert.are_not.equal(stored_a, stored_b)

        -- Verify A
        harpoon:set_sub_project("project-a")
        eq(1, harpoon:list():length())
        eq(stored_a, harpoon:list():get(1).value)

        -- Verify B
        harpoon:set_sub_project("project-b")
        eq(1, harpoon:list():length())
        eq(stored_b, harpoon:list():get(1).value)
    end)

    it("find_sub_projects returns sub-project names", function()
        -- Initially no sub-projects
        local initial = harpoon:find_sub_projects()
        eq(0, #initial)

        -- Create sub-projects by switching and adding data
        harpoon:set_sub_project("alpha")
        local file_1 = os.tmpname()
        utils.create_file(file_1, { "test" }, 1, 0)
        harpoon:list():add()

        harpoon:set_sub_project("beta")
        local file_2 = os.tmpname()
        utils.create_file(file_2, { "test" }, 1, 0)
        harpoon:list():add()

        harpoon:set_sub_project(nil)

        local projects = harpoon:find_sub_projects()
        table.sort(projects)
        eq({ "alpha", "beta" }, projects)
    end)

    it("delete_sub_project removes the sub-project data", function()
        -- Create a sub-project with data
        harpoon:set_sub_project("to-delete")
        local file = os.tmpname()
        utils.create_file(file, { "test" }, 1, 0)
        harpoon:list():add()

        -- Switch back to default and delete
        harpoon:set_sub_project(nil)
        harpoon:delete_sub_project("to-delete")

        -- Verify it's gone
        local projects = harpoon:find_sub_projects()
        eq(0, #projects)
    end)

    it("deleting active sub-project reverts to default", function()
        harpoon:set_sub_project("temp-project")
        local file = os.tmpname()
        utils.create_file(file, { "test" }, 1, 0)
        harpoon:list():add()

        harpoon:delete_sub_project("temp-project")

        eq(nil, harpoon.active_sub_project)
        eq("testies", harpoon:get_current_key())
    end)

    it("cannot delete the default project", function()
        local ok = pcall(function()
            harpoon:delete_sub_project("testies")
        end)
        eq(false, ok)
    end)

    it("cannot delete with empty name", function()
        local ok = pcall(function()
            harpoon:delete_sub_project("")
        end)
        eq(false, ok)
    end)

    it("persists active sub-project across reload", function()
        harpoon:set_sub_project("persistent-project")

        -- Simulate session restart by reloading and re-running setup
        -- The before_each helper reloads harpoon, but we need to
        -- preserve the data file. So we manually reload here.
        local Data_mod = require("harpoon.data")
        local config = Config.get_default_config()
        config.settings.key = function()
            return "testies"
        end
        local data = Data_mod.Data:new(config)

        -- Check the raw data has the metadata stored
        local default_entry =
            data:data("testies", Data_mod.ACTIVE_SUB_PROJECT_KEY)
        eq("persistent-project", default_entry)
    end)

    it("each sub-project supports its own named lists", function()
        -- Use a custom list name in the default context
        harpoon:set_sub_project(nil)
        local file_default = os.tmpname()
        utils.create_file(file_default, { "default" }, 1, 0)
        harpoon:list("terminals"):add()
        eq(1, harpoon:list("terminals"):length())
        local stored_default = harpoon:list("terminals"):get(1).value

        -- Switch to sub-project: custom list should be empty
        harpoon:set_sub_project("feature-x")
        eq(0, harpoon:list("terminals"):length())

        -- Add to sub-project's custom list
        local file_feature = os.tmpname()
        utils.create_file(file_feature, { "feature" }, 1, 0)
        harpoon:list("terminals"):add()
        eq(1, harpoon:list("terminals"):length())

        -- Verify default context's custom list is unchanged
        harpoon:set_sub_project(nil)
        eq(1, harpoon:list("terminals"):length())
        eq(stored_default, harpoon:list("terminals"):get(1).value)
    end)
end)
