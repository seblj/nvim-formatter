local config = require('formatter.config')
local text_edit = require('formatter.text_edit')
local a = require('formatter.async')
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
---@field range FormatRange | nil
---@field inital_changedtick number
---@field bufnr number
---@field confs FiletypeConfig | nil
---@field is_formatting boolean
---@field input table
local Format = {}

---@param range number[] | false
---@param bufnr? number
function Format:new(range, bufnr)
    local o = {}
    setmetatable(o, { __index = self })

    o.bufnr = bufnr or vim.api.nvim_get_current_buf()
    o.inital_changedtick = vim.api.nvim_buf_get_changedtick(o.bufnr)
    local start_line = range and range[1] or 1
    local end_line = range and range[2] or -1

    local input = vim.api.nvim_buf_get_lines(o.bufnr, 0, -1, false)

    o.range = end_line ~= -1 and { start = start_line, ['end'] = end_line } or nil

    o.is_formatting = false

    o.confs = config.get_ft_configs(o.bufnr, vim.bo[o.bufnr].ft)
    o.input = input

    return o
end

local asystem = a.wrap(vim.system, 3)

local execute = function(bufnr, conf, input)
    if vim.fn.executable(conf.exe) ~= 1 then
        a.scheduler()
        vim.notify_once(string.format('%s: executable not found', conf.exe), vim.log.levels.ERROR, notify_opts)
        return nil
    end

    if conf.cond and not conf.cond() then
        return nil
    end

    local out = asystem({ conf.exe, unpack(conf.args or {}) }, {
        cwd = conf.cwd,
        -- `get_node_text` returns string[] | string
        stdin = type(input) == 'table' and table.concat(input, '\n') or input,
    })

    if out.code ~= 0 then
        a.scheduler()
        local errmsg = out.stderr and out.stderr or out.stdout
        vim.notify(
            string.format(
                'Failed to format %s with %s%s',
                vim.api.nvim_buf_get_name(bufnr),
                conf.exe,
                errmsg and ': ' .. errmsg or ''
            ),
            vim.log.levels.ERROR,
            notify_opts
        )
        return nil
    end

    local stdout = out.stdout:sub(-1) == '\n' and out.stdout or out.stdout .. '\n'
    return vim.iter(stdout:gmatch('([^\n]*)\n')):totable()
end

---@return string[]
local get_injection_output = function(output, input)
    -- Need to sort it to start backwards to not mess with the range
    table.sort(output, function(_a, b)
        return _a[1].start_line > b[1].start_line
    end)

    local current_output = vim.deepcopy(input)
    for _, injection in ipairs(output) do
        for _ = injection[1].start_line, injection[1].end_line, 1 do
            table.remove(current_output, injection[1].start_line)
        end
        for i, text in ipairs(injection[1].output) do
            table.insert(current_output, injection[1].start_line + i - 1, text)
        end
    end
    return current_output
end

---@param text string[]
---@param ft string
---@param start_line number
local function try_transform_text(text, ft, start_line)
    local conf = config.get().treesitter.auto_indent[ft]
    if not conf or ((type(conf) == 'function') and not conf()) then
        return text
    end

    local col = vim.fn.match(vim.fn.getline(start_line), '\\S') --[[@as number]]
    return vim.iter.map(function(val)
        return string.format('%s%s', string.rep(' ', col), val)
    end, text)
end

---@param input string[]
function Format:run_injections(input)
    local injections = self:find_injections(input)

    local jobs = vim.iter.map(function(injection)
        return a.void(function(cb)
            local output = self:run(injection.confs, injection.input)
            output = try_transform_text(output, injection.ft, injection.start_line)
            cb({ output = output, start_line = injection.start_line, end_line = injection.end_line })
        end)
    end, injections)

    local res = a.join(jobs, 10)

    return get_injection_output(res, input)
end

---@param format Format
---@param type "basic" | "injections" | "all"
local function run(format, type)
    if type == 'basic' then
        local output = format:run(format.confs, format.input)
        format:insert(output)
    elseif type == 'injections' then
        local output = format:run_injections(format.input)
        format:insert(output)
    else
        local output = format:run(format.confs, format.input)
        a.scheduler()
        local ok, res = pcall(function()
            return format:run_injections(output)
        end)
        if not ok then
            format:insert(output)
        else
            format:insert(res)
        end
    end
end

---@param format Format
---@param type "basic" | "injections" | "all"
local start = a.void(function(format, type)
    local ok, res = pcall(run, format, type)
    format.is_formatting = false
    if not ok then
        error(res)
    end
end)

---@param type "all" | "basic" | "injections"
function Format:start(type)
    if not vim.bo[self.bufnr].modifiable then
        return vim.notify('Buffer is not modifiable', vim.log.levels.INFO, notify_opts)
    end

    vim.api.nvim_create_autocmd({ 'ExitPre', 'VimLeavePre' }, {
        pattern = '*',
        group = vim.api.nvim_create_augroup('FormatterAsync', { clear = true }),
        callback = function()
            vim.wait(5000, function()
                return self.is_formatting == false
            end, 10)
        end,
    })

    self.is_formatting = true
    start(self, type)
end

---@param output string[]
function Format:insert(output)
    if output and not vim.deep_equal(output, self.input) then
        vim.schedule(function()
            if self.inital_changedtick ~= vim.api.nvim_buf_get_changedtick(self.bufnr) then
                vim.notify('Buffer changed while formatting', vim.log.levels.INFO, notify_opts)
                return
            end
            text_edit.apply_text_edits(self.bufnr, self.input, output)
            vim.api.nvim_buf_call(self.bufnr, function()
                vim.cmd.update({ mods = { emsg_silent = true, silent = true, noautocmd = true } })
            end)
        end)
    end
end

---Returns the output from formatting the buffer with all configs
---@param confs FiletypeConfig[]
---@param input string[]
---@return string[]
function Format:run(confs, input)
    local sliced_input = self.range and vim.iter(input):slice(self.range.start, self.range['end']):totable() or input

    local formatted_output = vim.iter(confs):fold(sliced_input, function(acc, v)
        return execute(self.bufnr, v, acc) or acc
    end)

    if self.range then
        local output = vim.deepcopy(input)
        for _ = self.range.start, self.range['end'], 1 do
            table.remove(output, self.range.start)
        end
        for i, text in ipairs(formatted_output) do
            table.insert(output, self.range.start + i - 1, text)
        end
        return output
    else
        return formatted_output
    end
end
---@param t table?
---@param ft string
---@return boolean
local function contains(t, ft)
    return vim.iter(t or {}):any(function(v)
        return v == ft or v == '*'
    end)
end

---@param conf? table<FiletypeConfig>
---@param exe string
---@return boolean
local function same_executable(conf, exe)
    return vim.iter(conf or {}):any(function(c)
        return c.exe == exe
    end)
end

---@param ft string
---@return table<FiletypeConfig> | nil
function Format:get_injected_confs(ft)
    local confs = config.get_ft_configs(self.bufnr, ft)
    if vim.bo[self.bufnr].ft == ft or not confs then
        return nil
    end

    local disable_injected = config.get().treesitter.disable_injected[vim.bo[self.bufnr].ft]

    -- Only try to format an injected language if it is not disabled with
    -- `disable_injected` or if the executable is different. Check the
    -- executable because we should not format with prettier typescript inside
    -- vue-files. Prettier for vue should do the entire file
    return vim.iter.map(function(c)
        if not contains(disable_injected, ft) and not same_executable(self.confs, c.exe) then
            return c
        end
    end, confs)
end

---@param text string
---@return number Number of newlines at the start of the node text
local function get_starting_newlines(text)
    local lines = vim.split(text, '\n')
    return vim.iter(lines):enumerate():find(function(_, line)
        return line ~= ''
    end) - 1
end

---@param bufnr number
---@param lang string
---@return string?
local function lang_to_ft(bufnr, lang)
    local filetypes = vim.treesitter.language.get_filetypes(lang)
    return vim.iter(filetypes):find(function(ft)
        return config.get_ft_configs(bufnr, ft)
    end)
end

---@param output string[]
---@return Injection[]
function Format:find_injections(output)
    local injections = {}
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, output)

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
            local ft = lang_to_ft(self.bufnr, lang) or vim.bo[self.bufnr].ft
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
