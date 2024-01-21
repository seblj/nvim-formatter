local config = require('formatter.config')
local text_edit = require('formatter.text_edit')
local notify_opts = { title = 'Formatter' }

---@class FormatRange
---@field start number
---@field end number

---@class Injection
---@field start_line number
---@field end_line number
---@field ft string
---@field confs FiletypeConfig[]
---@field input string[]|string

---@class FormattedInjection
---@field output table
---@field start_line number
---@field end_line number

---@class Format
---@field range FormatRange
---@field async boolean
---@field inital_changedtick number
---@field bufnr number
---@field confs FiletypeConfig | nil
---@field is_formatting boolean
---@field calculated_injections FormattedInjection[]
---@field injections Injection[]
---@field input table
---@field current_output table
local Format = {}

---@param range number[] | false
---@param async boolean
---@param bufnr? number
function Format:new(range, async, bufnr)
    local o = {}
    setmetatable(o, { __index = self })

    o.bufnr = bufnr or vim.api.nvim_get_current_buf()
    o.inital_changedtick = vim.api.nvim_buf_get_changedtick(o.bufnr)
    o.async = async
    local start_line = range and range[1] or 1
    local end_line = range and range[2] or -1

    local input = vim.api.nvim_buf_get_lines(o.bufnr, start_line - 1, end_line, false)

    o.range = { start = start_line, ['end'] = end_line == -1 and #input or end_line }

    o.is_formatting = false
    o.calculated_injections = {}

    o.confs = config.get_ft_configs(vim.bo[o.bufnr].ft)
    o.injections = {}
    o.input = input
    o.current_output = vim.deepcopy(input)

    return o
end

---@param type "all" | "basic" | "injections"
---@param exit_pre? boolean Whether to set ExitPre autocmd or not
function Format:start(type, exit_pre)
    if not vim.bo[self.bufnr].modifiable then
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
        if self.confs then
            self:run_basic(true)
        else
            self:run_injections()
        end
    elseif type == 'injections' then
        self:run_injections()
    elseif type == 'basic' then
        if not self.confs then
            return vim.notify_once(
                string.format('No config found for %s', vim.bo[self.bufnr].ft),
                vim.log.levels.INFO,
                notify_opts
            )
        end
        self:run_basic(false)
    end
end

-- Inserts self.current_output into the buffer
function Format:insert()
    if not vim.deep_equal(self.current_output, self.input) then
        vim.schedule(function()
            if self.async and self.inital_changedtick ~= vim.api.nvim_buf_get_changedtick(self.bufnr) then
                self.is_formatting = false
                return vim.notify('Buffer changed while formatting', vim.log.levels.INFO, notify_opts)
            end
            text_edit.apply_text_edits(self.bufnr, self.input, self.current_output)
            vim.api.nvim_buf_call(self.bufnr, function()
                vim.cmd.update({ mods = { emsg_silent = true, silent = true, noautocmd = true } })
            end)
            self.is_formatting = false
        end)
    else
        self.is_formatting = false
    end
end

---@param conf FiletypeConfig
---@param input string[]|string
---@param on_success fun(stdout:string[])
function Format:execute(conf, input, on_success)
    if vim.fn.executable(conf.exe) ~= 1 then
        self.is_formatting = false
        return vim.notify_once(string.format('%s: executable not found', conf.exe), vim.log.levels.ERROR, notify_opts)
    end

    if conf.cond and not conf.cond() then
        self.is_formatting = false
        return
    end

    local on_exit = function(out)
        if out.code ~= 0 then
            self.is_formatting = false
            vim.schedule(function()
                local errmsg = out.stderr and out.stderr or out.stdout
                vim.notify(
                    string.format(
                        'Failed to format %s with %s%s',
                        vim.api.nvim_buf_get_name(self.bufnr),
                        conf.exe,
                        errmsg and ': ' .. errmsg or ''
                    ),
                    vim.log.levels.ERROR,
                    notify_opts
                )
            end)
        else
            local output = {}
            local stdout = out.stdout:sub(-1) == '\n' and out.stdout or out.stdout .. '\n'
            for k in stdout:gmatch('([^\n]*)\n') do
                table.insert(output, k)
            end
            on_success(output)
        end
    end

    local out = vim.system({ conf.exe, unpack(conf.args) }, {
        cwd = conf.cwd or vim.fs.dirname(vim.api.nvim_buf_get_name(self.bufnr)),
        -- `get_node_text` returns string[] | string
        stdin = type(input) == 'table' and table.concat(input, '\n') or input,
    }, self.async and on_exit or nil)
    if not self.async then
        on_exit(out:wait())
    end
end

function Format:run(conf, confs, out, f)
    if not confs[conf] then
        return f(out)
    end
    self:execute(confs[conf], out, function(stdout)
        vim.schedule(function()
            self:run(conf + 1, confs, stdout, f)
        end)
    end)
end

---Runs basic formatter for buffer.
---Tries to run formatter for treesitter injections. Will insert into buffer
---later when formatting injections
---@param run_treesitter boolean
function Format:run_basic(run_treesitter)
    self:run(1, self.confs, self.current_output, function(out)
        self.current_output = out
        if run_treesitter then
            return vim.schedule(function()
                self:run_injections()
            end)
        end
        return self:insert()
    end)
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

---@param text string[]
---@param ft string
---@param start_line number
local function try_transform_text(text, ft, start_line)
    local conf = config.get().treesitter.auto_indent[ft]
    if not conf then
        return text
    end

    if type(conf) == 'function' then
        conf = conf()
        if not conf then
            return text
        end
    end

    local col = vim.fn.match(vim.fn.getline(start_line), '\\S') --[[@as number]]
    return vim.tbl_map(function(val)
        return string.format('%s%s', string.rep(' ', col), val)
    end, text)
end

function Format:run_injections()
    self.injections = self:find_injections()
    if #self.injections > 0 then
        for _, injection in ipairs(self.injections) do
            self:run(1, injection.confs, injection.input, function(out)
                out = try_transform_text(out, injection.ft, injection.start_line)
                table.insert(
                    self.calculated_injections,
                    { output = out, start_line = injection.start_line, end_line = injection.end_line }
                )
                if #self.calculated_injections == #self.injections then
                    self:set_current_output()
                    self:insert()
                end
            end)
        end
    else
        self:insert()
    end
end

---@param t table?
---@param ft string
---@return boolean
local function contains(t, ft)
    if not t then
        return false
    end
    return vim.tbl_contains(t, ft) or vim.tbl_contains(t, '*')
end

---@param conf? table<FiletypeConfig>
---@param exe string
---@return boolean
local function same_executable(conf, exe)
    for _, c in ipairs(conf or {}) do
        if c.exe == exe then
            return true
        end
    end
    return false
end

---@param ft string
---@return table<FiletypeConfig> | nil
function Format:get_injected_confs(ft)
    local confs = config.get_ft_configs(ft)
    if vim.bo[self.bufnr].ft == ft or not confs then
        return nil
    end

    local disable_injected = config.get().treesitter.disable_injected[vim.bo[self.bufnr].ft]

    -- Only try to format an injected language if it is not disabled with
    -- `disable_injected` or if the executable is different. Check the
    -- executable because we should not format with prettier typescript inside
    -- vue-files. Prettier for vue should do the entire file
    local injected_confs = {}
    for _, c in ipairs(confs) do
        if not contains(disable_injected, ft) and not same_executable(self.confs, c.exe) then
            injected_confs[#injected_confs + 1] = c
        end
    end

    return injected_confs
end

---@param text string
---@return number Number of newlines at the start of the node text
local function get_starting_newlines(text)
    local lines = vim.split(text, '\n')
    local newlines = 0
    for _, line in ipairs(lines) do
        if line ~= '' then
            return newlines
        end
        newlines = newlines + 1
    end
    return newlines
end

---@param lang string
---@return string?
local function lang_to_ft(lang)
    local fts = vim.treesitter.language.get_filetypes(lang)
    for _, ft in ipairs(fts) do
        if config.get_ft_configs(ft) then
            return ft
        end
    end
    return nil
end

---@return Injection[]
function Format:find_injections()
    local injections = {}
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, self.current_output)

    local parser_lang = vim.treesitter.language.get_lang(vim.bo[self.bufnr].ft)
    local ok, parser = pcall(vim.treesitter.get_parser, buf, parser_lang)
    if not ok or not parser then
        return injections
    end
    parser:parse(true)

    for lang, child in pairs(parser:children()) do
        for _, tree in ipairs(child:trees()) do
            local root = tree:root()
            local range = { root:range() }
            local start_line, end_line = range[1], range[3]
            local ft = lang_to_ft(lang) or vim.bo[self.bufnr].ft
            local confs = self:get_injected_confs(ft)
            if confs and #confs > 0 then
                local text = vim.treesitter.get_node_text(root, buf)
                if text then
                    start_line = start_line + get_starting_newlines(text)
                    -- Only continue if end_line is higher than start_line
                    if end_line > start_line then
                        table.insert(injections, {
                            start_line = start_line + 1,
                            end_line = end_line,
                            confs = confs,
                            input = text,
                            ft = ft,
                        })
                    end
                end
            end
        end
    end
    return injections
end

return Format
