local utils = require("harpoon.test.utils")
local Buffer = require("harpoon.buffer")
local harpoon = require("harpoon")

local eq = assert.are.same
local be = utils.before_each(os.tmpname())

describe("harpoon", function()
    before_each(function()
        be()
        harpoon = require("harpoon")
    end)

    it("open the ui without any items in the list", function()
        harpoon.ui:toggle_quick_menu(harpoon:list())

        local bufnr = harpoon.ui.bufnr
        local win_id = harpoon.ui.win_id

        eq(vim.api.nvim_buf_is_valid(bufnr), true)
        eq(vim.api.nvim_win_is_valid(win_id), true)

        harpoon.ui:toggle_quick_menu()

        eq(vim.api.nvim_buf_is_valid(bufnr), false)
        eq(vim.api.nvim_win_is_valid(win_id), false)
        eq(harpoon.ui.bufnr, nil)
        eq(harpoon.ui.win_id, nil)
    end)

    it("delete file from ui contents and save", function()
        local created_files = utils.fill_list_with_files(3, harpoon:list())
        eq(harpoon:list():length(), 3)

        harpoon.ui:toggle_quick_menu(harpoon:list())
        table.remove(created_files, 2)
        Buffer.set_contents(harpoon.ui.bufnr, created_files)
        harpoon.ui:save()
        harpoon.ui:toggle_quick_menu()

        eq(harpoon:list():length(), 2)
        eq(harpoon:list():display(), created_files)
    end)

    it("add file from ui contents and save", function()
        local list = harpoon:list()
        local created_files = utils.fill_list_with_files(3, list)
        table.insert(created_files, os.tmpname())

        eq(list:length(), 3)

        harpoon.ui:toggle_quick_menu(list)
        Buffer.set_contents(harpoon.ui.bufnr, created_files)
        harpoon.ui:save()
        harpoon.ui:toggle_quick_menu()

        eq(list:length(), 4)
        eq(list:display(), created_files)
    end)

    it("edit ui but toggle should not save", function()
        local list = harpoon:list()
        local created_files = utils.fill_list_with_files(3, list)

        eq(list:length(), 3)

        harpoon.ui:toggle_quick_menu(list)
        Buffer.set_contents(harpoon.ui.bufnr, {})
        harpoon.ui:toggle_quick_menu()

        eq(list:length(), 3)
        eq(created_files, list:display())
    end)

    it("ui with replace_at", function()
        local one_f = os.tmpname()
        local one = utils.create_file(one_f, { "one" })
        local three_f = os.tmpname()
        local three = utils.create_file(three_f, { "three" })
        local context = { row = 1, col = 0 }

        eq(0, harpoon:list():length())
        vim.api.nvim_set_current_buf(three)

        harpoon:list():replace_at(3)
        eq(3, harpoon:list():length())

        vim.api.nvim_set_current_buf(one)
        harpoon:list():replace_at(1)
        eq(3, harpoon:list():length())

        harpoon.ui:toggle_quick_menu(harpoon:list())

        utils.key("<CR>")

        eq(3, harpoon:list():length())
        eq({
            { value = one_f, context = context },
            nil,
            { value = three_f, context = context },
        }, harpoon:list().items)
    end)

    it("using :q to leave harpoon should quit everything", function()
        harpoon.ui:toggle_quick_menu(harpoon:list())

        local bufnr = harpoon.ui.bufnr
        local win_id = harpoon.ui.win_id

        eq(vim.api.nvim_buf_is_valid(bufnr), true)
        eq(vim.api.nvim_win_is_valid(win_id), true)
        eq(vim.api.nvim_get_current_buf(), bufnr)

        vim.cmd([[ q! ]]) -- TODO: I shouldn't need q! here

        eq(vim.api.nvim_buf_is_valid(bufnr), false)
        eq(vim.api.nvim_win_is_valid(win_id), false)
        eq(harpoon.ui.bufnr, nil)
        eq(harpoon.ui.win_id, nil)
    end)

    it(
        "closing toggle_quick_menu with save_on_toggle should save contents",
        function()
            harpoon:setup({ settings = { save_on_toggle = true } })
            local list = harpoon:list()
            local created_files = utils.fill_list_with_files(3, list)

            harpoon.ui:toggle_quick_menu(list)
            table.remove(created_files, 2)
            Buffer.set_contents(harpoon.ui.bufnr, created_files)
            harpoon.ui:toggle_quick_menu()

            eq(list:length(), 2)
            eq(list:display(), created_files)
        end
    )

    it("exiting the ui with something like <C-w><C-w>", function()
        harpoon.ui:toggle_quick_menu(harpoon:list())

        local bufnr = harpoon.ui.bufnr
        local win_id = harpoon.ui.win_id

        eq(vim.api.nvim_buf_is_valid(bufnr), true)
        eq(vim.api.nvim_win_is_valid(win_id), true)
        eq(vim.api.nvim_get_current_buf(), bufnr)

        utils.key("<C-w><C-w>")

        eq(vim.api.nvim_buf_is_valid(bufnr), false)
        eq(vim.api.nvim_win_is_valid(win_id), false)
        eq(harpoon.ui.bufnr, nil)
        eq(harpoon.ui.win_id, nil)
    end)

    it("exiting the ui with q (see harpoon.buffer)", function()
        harpoon.ui:toggle_quick_menu(harpoon:list())

        local bufnr = harpoon.ui.bufnr
        local win_id = harpoon.ui.win_id

        eq(vim.api.nvim_buf_is_valid(bufnr), true)
        eq(vim.api.nvim_win_is_valid(win_id), true)
        eq(vim.api.nvim_get_current_buf(), bufnr)

        utils.key("q")

        eq(vim.api.nvim_buf_is_valid(bufnr), false)
        eq(vim.api.nvim_win_is_valid(win_id), false)
        eq(harpoon.ui.bufnr, nil)
        eq(harpoon.ui.win_id, nil)
    end)

    it("exiting the ui with <Esc> (see harpoon.buffer)", function()
        harpoon.ui:toggle_quick_menu(harpoon:list())

        local bufnr = harpoon.ui.bufnr
        local win_id = harpoon.ui.win_id

        eq(vim.api.nvim_buf_is_valid(bufnr), true)
        eq(vim.api.nvim_win_is_valid(win_id), true)
        eq(vim.api.nvim_get_current_buf(), bufnr)

        utils.key("<Esc>")

        eq(vim.api.nvim_buf_is_valid(bufnr), false)
        eq(vim.api.nvim_win_is_valid(win_id), false)
        eq(harpoon.ui.bufnr, nil)
        eq(harpoon.ui.win_id, nil)
    end)

    it("exiting the ui with something like :bprev / :bnext", function()
        harpoon.ui:toggle_quick_menu(harpoon:list())

        local bufnr = harpoon.ui.bufnr
        local win_id = harpoon.ui.win_id

        eq(vim.api.nvim_buf_is_valid(bufnr), true)
        eq(vim.api.nvim_win_is_valid(win_id), true)
        eq(vim.api.nvim_get_current_buf(), bufnr)

        -- Some people use keymaps that trigger these commands
        vim.cmd("bprev")

        eq(vim.api.nvim_buf_is_valid(bufnr), false)
        eq(vim.api.nvim_win_is_valid(win_id), false)
        eq(harpoon.ui.bufnr, nil)
        eq(harpoon.ui.win_id, nil)
    end)
end)

describe("harpoon sub-project ui", function()
    before_each(function()
        be()
        harpoon = require("harpoon")
    end)

    it("open sub-project menu with no sub-projects", function()
        harpoon.ui:toggle_sub_project_menu(harpoon)

        local bufnr = harpoon.ui.bufnr
        local win_id = harpoon.ui.win_id

        eq(vim.api.nvim_buf_is_valid(bufnr), true)
        eq(vim.api.nvim_win_is_valid(win_id), true)

        -- Buffer should be empty (no sub-projects)
        local contents = Buffer.get_contents(bufnr)
        eq({ "" }, contents)

        harpoon.ui:toggle_sub_project_menu(nil)

        eq(harpoon.ui.bufnr, nil)
        eq(harpoon.ui.win_id, nil)
    end)

    it("open sub-project menu with existing sub-projects", function()
        -- Create some sub-projects via the API
        harpoon:set_sub_project("alpha")
        local f1 = os.tmpname()
        utils.create_file(f1, { "test" }, 1, 0)
        harpoon:list():add()

        harpoon:set_sub_project("beta")
        local f2 = os.tmpname()
        utils.create_file(f2, { "test" }, 1, 0)
        harpoon:list():add()

        harpoon:set_sub_project(nil)

        harpoon.ui:toggle_sub_project_menu(harpoon)

        local contents = Buffer.get_contents(harpoon.ui.bufnr)
        table.sort(contents)
        eq({ "alpha", "beta" }, contents)

        harpoon.ui:toggle_sub_project_menu(nil)
    end)

    it("delete sub-project from UI", function()
        -- Create a sub-project
        harpoon:set_sub_project("to-delete")
        local f = os.tmpname()
        utils.create_file(f, { "test" }, 1, 0)
        harpoon:list():add()
        harpoon:set_sub_project(nil)

        eq(1, #harpoon:find_sub_projects())

        -- Open the sub-project menu and remove the line
        harpoon.ui:toggle_sub_project_menu(harpoon)
        Buffer.set_contents(harpoon.ui.bufnr, {})
        harpoon.ui:save_sub_projects()
        harpoon.ui:toggle_sub_project_menu(nil)

        eq(0, #harpoon:find_sub_projects())
    end)

    it("add sub-project from UI", function()
        eq(0, #harpoon:find_sub_projects())

        harpoon.ui:toggle_sub_project_menu(harpoon)
        Buffer.set_contents(harpoon.ui.bufnr, { "new-project" })
        harpoon.ui:save_sub_projects()
        harpoon.ui:toggle_sub_project_menu(nil)

        local projects = harpoon:find_sub_projects()
        eq(1, #projects)
        eq("new-project", projects[1])
    end)

    it("select sub-project from UI switches context", function()
        -- Create a sub-project
        harpoon:set_sub_project("my-feature")
        local f = os.tmpname()
        utils.create_file(f, { "test" }, 1, 0)
        harpoon:list():add()
        harpoon:set_sub_project(nil)

        eq(nil, harpoon.active_sub_project)

        harpoon.ui:toggle_sub_project_menu(harpoon)

        -- Move cursor to line 1 and select
        vim.api.nvim_win_set_cursor(harpoon.ui.win_id, { 1, 0 })
        harpoon.ui:select_sub_project_item()

        eq("my-feature", harpoon.active_sub_project)
        eq(nil, harpoon.ui.win_id)
        eq(nil, harpoon.ui.bufnr)
    end)

    it("edit (rename) sub-project from UI", function()
        -- Create a sub-project
        harpoon:set_sub_project("old-name")
        local f = os.tmpname()
        utils.create_file(f, { "test" }, 1, 0)
        harpoon:list():add()
        harpoon:set_sub_project(nil)

        harpoon.ui:toggle_sub_project_menu(harpoon)
        Buffer.set_contents(harpoon.ui.bufnr, { "new-name" })
        harpoon.ui:save_sub_projects()
        harpoon.ui:toggle_sub_project_menu(nil)

        local projects = harpoon:find_sub_projects()
        eq(1, #projects)
        eq("new-name", projects[1])
    end)

    it("toggle without save discards changes", function()
        -- Create a sub-project
        harpoon:set_sub_project("keep-me")
        local f = os.tmpname()
        utils.create_file(f, { "test" }, 1, 0)
        harpoon:list():add()
        harpoon:set_sub_project(nil)

        eq(1, #harpoon:find_sub_projects())

        -- Open, clear buffer, but close without saving
        harpoon.ui:toggle_sub_project_menu(harpoon)
        Buffer.set_contents(harpoon.ui.bufnr, {})
        harpoon.ui:toggle_sub_project_menu(nil)

        -- Sub-project should still exist
        eq(1, #harpoon:find_sub_projects())
    end)

    it("close sub-project menu with q", function()
        harpoon.ui:toggle_sub_project_menu(harpoon)

        local bufnr = harpoon.ui.bufnr
        local win_id = harpoon.ui.win_id

        eq(vim.api.nvim_buf_is_valid(bufnr), true)
        eq(vim.api.nvim_win_is_valid(win_id), true)

        utils.key("q")

        eq(vim.api.nvim_buf_is_valid(bufnr), false)
        eq(vim.api.nvim_win_is_valid(win_id), false)
        eq(harpoon.ui.bufnr, nil)
        eq(harpoon.ui.win_id, nil)
    end)
end)
