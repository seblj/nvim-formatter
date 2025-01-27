local M = {}

---@alias NvimFormatterFiletypeConfigUnion string | NvimFormatterFiletypeConfig | fun(): string | NvimFormatterFiletypeConfig

---@class NvimFormatterConfig
---@field filetype table<string, NvimFormatterFiletypeConfigUnion | NvimFormatterFiletypeConfigUnion[]>
---@field format_on_save? boolean | fun(): boolean
---@field treesitter? NvimFormatterTreesitterConfig
---@field lsp? string[]

---@class NvimFormatterTreesitterConfig
---@field auto_indent? table<string, boolean | fun(): boolean>
---@field disable_injected? table<string, table<string>?>

---@class NvimFormatterFiletypeConfig
---@field exe string
---@field cond? function
---@field args? table
---@field cwd? string
---@field disable_injected? string | table

---@type NvimFormatterConfig
local config = {
    filetype = {},
    format_on_save = false,
    treesitter = { auto_indent = {}, disable_injected = { ['*'] = { '_' } } },
}

---@param opts NvimFormatterConfig
---@return NvimFormatterConfig
function M.set(opts)
    config = vim.tbl_deep_extend('force', config, opts or {})
    return config
end

---@return NvimFormatterConfig
function M.get()
    return config
end

---@param conf string
---@return NvimFormatterFiletypeConfig
local function string_config(bufnr, conf)
    local split = vim.split(conf, ' ')
    return {
        exe = split[1],
        args = { unpack(split, 2, #split) },
        cwd = vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr)),
    }
end

---@param bufnr number
---@param f NvimFormatterFiletypeConfig | string | fun(): NvimFormatterFiletypeConfig
---@return NvimFormatterFiletypeConfig
local function parse_configs(bufnr, f)
    if type(f) == 'function' then
        return parse_configs(bufnr, f())
    elseif type(f) == 'string' then
        return string_config(bufnr, f)
    else
        f.cwd = f.cwd or vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
        return f
    end
end

---@param ft string
---@return table<NvimFormatterFiletypeConfig> | nil
function M.get_ft_configs(bufnr, ft)
    local f = config.filetype[ft] or config.filetype['_']
    if not f then
        return nil
    end
    if type(f) == 'table' and f[1] ~= nil then
        return vim.iter(f)
            :map(function(c)
                return parse_configs(bufnr, c)
            end)
            :totable()
    end
    return { parse_configs(bufnr, f) }
end

return M
