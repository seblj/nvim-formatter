local config = require('formatter.config')
local parsers = require('nvim-treesitter.parsers')
local util = require('formatter.util')
local notify_opts = { title = 'Formatter' }

---@class Injection
---@field start_line number
---@field end_line number
---@field conf FiletypeConfig
---@field input table

---@class FormattedInjection
---@field output table
---@field start_line number
---@field end_line number

---@class Format
---@field start_line number
---@field end_line number
---@field bufnr number
---@field conf FiletypeConfig | nil
---@field is_formatting boolean
---@field calculated_injections FormattedInjection[]
---@field injections Injection[]
---@field input table
---@field current_output table
local Format = {}

---@param start_line? number
---@param end_line? number
function Format:new(start_line, end_line)
    setmetatable({}, self)
    self.start_line = start_line or 1
    self.end_line = end_line or -1
    self.inital_changedtick = vim.api.nvim_buf_get_changedtick(0)
    self.async = config.get('format_async')

    local input = vim.api.nvim_buf_get_lines(0, self.start_line - 1, self.end_line, false)

    self.__index = self
    self.is_formatting = false
    self.bufnr = vim.api.nvim_get_current_buf()
    self.calculated_injections = {}

    self.conf = config.get_ft_config(vim.bo.ft)
    self.injections = {}
    self.input = input
    self.current_output = input

    return self
end

---@param type "all" | "basic" | "injections"
---@param exit_pre boolean Whether to set ExitPre autocmd or not
function Format:run(type, exit_pre)
    if not vim.bo.modifiable then
        return vim.notify('Buffer is not modifiable', vim.log.levels.INFO, notify_opts)
    end

    self.is_formatting = true
    if exit_pre and self.async then
        vim.api.nvim_create_autocmd('ExitPre', {
            pattern = '*',
            group = vim.api.nvim_create_augroup('FormatterAsync', { clear = true }),
            callback = function()
                vim.wait(5000, function()
                    ---@diagnostic disable-next-line: redundant-return-value
                    return self.is_formatting == false
                end, 10)
            end,
        })
    end

    if type == 'all' then
        -- Only try to run injections if there is no config for vim.bo.ft
        if self.conf then
            self:run_basic(true)
        else
            self:run_injections()
        end
    elseif type == 'injections' then
        self:run_injections()
    elseif type == 'basic' then
        self:run_basic(false)
    end
end

-- Inserts self.current_output into the buffer
function Format:insert()
    if not vim.deep_equal(self.current_output, self.input) then
        vim.schedule(function()
            if self.async and self.inital_changedtick ~= vim.api.nvim_buf_get_changedtick(0) then
                return vim.notify(string.format('Buffer changed while formatting'), vim.log.levels.INFO, notify_opts)
            end
            local view = vim.fn.winsaveview()
            local marks = util.save_marks(self.bufnr)
            vim.api.nvim_buf_set_lines(self.bufnr, self.start_line - 1, self.end_line, false, self.current_output)
            vim.cmd.write({ mods = { emsg_silent = true, silent = true, noautocmd = true } })
            vim.fn.winrestview(view)
            util.restore_marks(self.bufnr, marks)
            self.is_formatting = false
        end)
    else
        self.is_formatting = false
    end
end

---Runs basic formatter for buffer.
---Tries to run formatter for treesitter injections. Will insert into buffer
---later when formatting injections
---@param run_treesitter boolean
function Format:run_basic(run_treesitter)
    if vim.fn.executable(self.conf.exe) ~= 1 then
        return vim.notify(string.format('%s: executable not found', self.conf.exe), vim.log.levels.ERROR, notify_opts)
    end
    if not self.conf then
        return vim.notify(string.format('No config found for %s', vim.bo.ft), vim.log.levels.INFO, notify_opts)
    end
    if self.conf.cond and not self.conf.cond() then
        return
    end

    local job = require('plenary.job'):new({
        command = self.conf.exe,
        args = self.conf.args or {},
        cwd = self.conf.cwd or vim.loop.cwd(),
        writer = self.current_output,
        on_exit = function(j, exit_code)
            if exit_code ~= 0 then
                vim.schedule(function()
                    vim.notify(
                        string.format('Failed to format: %s', table.concat(j:stderr_result())),
                        vim.log.levels.ERROR,
                        notify_opts
                    )
                end)
            else
                local output = j:result()
                self.current_output = output
                if run_treesitter then
                    vim.schedule(function()
                        self:run_injections()
                    end)
                else
                    self:insert()
                end
            end
        end,
    })

    if self.async then
        job:start()
    else
        job:sync()
    end
end

function Format:set_current_output()
    -- Need to sort it to start backwards to not mess with the range
    table.sort(self.calculated_injections, function(a, b)
        return a.start_line > b.start_line
    end)
    for _, injection in ipairs(self.calculated_injections) do
        for _ = injection.start_line, injection.end_line, 1 do
            table.remove(self.current_output, injection.start_line)
        end
        for i, text in ipairs(injection.output) do
            table.insert(self.current_output, injection.start_line + i - 1, text)
        end
    end
end

function Format:run_injections()
    self.injections = self:find_injections(self.current_output)
    if #self.injections > 0 then
        for _, injection in ipairs(self.injections) do
            self:_run_injections(injection)
        end
    else
        self:insert()
    end
end

-- Format injections
---@param injection Injection
function Format:_run_injections(injection)
    local start_line, end_line, conf, input = injection.start_line, injection.end_line, injection.conf, injection.input

    if vim.fn.executable(conf.exe) ~= 1 then
        return vim.notify(string.format('%s: executable not found', conf.exe), vim.log.levels.ERROR, notify_opts)
    end
    if conf.cond and not conf.cond() then
        return
    end

    local job = require('plenary.job'):new({
        command = conf.exe,
        args = conf.args or {},
        cwd = conf.cwd or vim.loop.cwd(),
        writer = input,
        on_exit = function(j, exit_code)
            if exit_code ~= 0 then
                vim.schedule(function()
                    vim.notify(
                        string.format('Failed to format: %s', table.concat(j:stderr_result())),
                        vim.log.levels.ERROR,
                        notify_opts
                    )
                end)
            else
                local output = j:result()
                table.insert(
                    self.calculated_injections,
                    { output = output, start_line = start_line, end_line = end_line }
                )
                if #self.calculated_injections == #self.injections then
                    self:set_current_output()
                    self:insert()
                end
            end
        end,
    })

    if self.async then
        job:start()
    else
        job:sync()
    end
end

---@param t table | string
---@param ft string
---@return boolean
local function contains(t, ft)
    if type(t) == 'string' then
        if t == '*' or t == ft then
            return true
        end
    elseif type(t) == 'table' then
        if vim.tbl_contains(t, ft) or vim.tbl_contains(t, '*') then
            return true
        end
    end
    return false
end

---@param conf FiletypeConfig
---@param ft string
---@return boolean
local function should_format(conf, ft)
    if conf.disable_as_injected and contains(conf.disable_as_injected, vim.bo.ft) then
        return false
    end

    local buf_ft_conf = config.get_ft_config(vim.bo.ft)
    if buf_ft_conf and buf_ft_conf.disable_injected and contains(buf_ft_conf.disable_injected, ft) then
        return false
    end

    return true
end

---@param text string
---@return number Number of newlines at the start of the node text
local function get_starting_newlines(text)
    local a = vim.split(text, '\n')
    local newlines = 0
    for _, t in ipairs(a) do
        if t ~= '' then
            return newlines
        end
        newlines = newlines + 1
    end
    return newlines
end

---@param input table
function Format:find_injections(input)
    local injections = {}
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, input)
    local parser = parsers.get_parser(buf, parsers.ft_to_lang(vim.bo.ft))
    if not parser then
        return injections
    end

    for lang, child in pairs(parser:children()) do
        for _, tree in ipairs(child._trees) do
            local root = tree:root()
            local range = { root:range() }
            local start_line, end_line = range[1] + 1, range[3]
            local ft = parsers.list.filetype or lang
            local conf = config.get_ft_config(ft)
            if conf and ft ~= vim.bo.ft and should_format(conf, ft) then
                local text = vim.treesitter.get_node_text(root, buf)
                start_line = start_line + get_starting_newlines(text)
                table.insert(injections, { start_line = start_line, end_line = end_line, conf = conf, input = text })
            end
        end
    end
    return injections
end

return Format
