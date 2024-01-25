local M = {}

---@class Config
---@field filetype table<string, string | table<string> | fun(): FiletypeConfig>
---@field format_on_save? boolean | fun(): boolean
---@field lsp? string[]
---@field treesitter? TreesitterConfig

---@class TreesitterConfig
---@field auto_indent? table<string, boolean | fun(): boolean>
---@field disable_injected? table<string, table<string>?>

---@class FiletypeConfig
---@field exe string
---@field cond? function
---@field args? table
---@field cwd? string
---@field disable_injected? string | table
---@field disable_as_injected? string | table

---@type Config
local config = {
    filetype = {},
    format_on_save = false,
    lsp = {},
    treesitter = { auto_indent = {}, disable_injected = {} },
}

---@param opts Config
---@return Config
function M.set(opts)
    config = vim.tbl_deep_extend('force', config, opts or {})
    return config
end

---@alias config_key "filetype"
---@param key? config_key
---@return Config | table<string, fun(): FiletypeConfig> | boolean
function M.get(key)
    if key and config[key] ~= nil then
        return config[key]
    end
    return config
end

---@param conf string
---@return FiletypeConfig
local function string_config(bufnr, conf)
    local split = vim.split(conf, ' ')
    return {
        exe = split[1],
        args = { unpack(split, 2, #split) },
        cwd = vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr)),
    }
end

---@param bufnr number
---@param f function
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
---@return table<FiletypeConfig> | nil
function M.get_ft_configs(bufnr, ft)
    local f = M.get('filetype')[ft]
    if not f then
        return nil
    end
    if type(f) == 'table' then
        return vim.iter.map(function(c)
            return parse_configs(bufnr, c)
        end, f)
    end
    return { parse_configs(bufnr, f) }
end

return M
