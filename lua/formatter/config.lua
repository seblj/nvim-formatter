local M = {}

---@class Config
---@field filetype table<string, string | table<string> | fun(): FiletypeConfig>
---@field format_async boolean
---@field format_on_save boolean | fun(): boolean
---@field lsp string[]

---@class FiletypeConfig
---@field exe string
---@field cond? function
---@field args? table
---@field cwd? string
---@field disable_injected? string | table
---@field disable_as_injected? string | table

---@type Config
local config = {
    format_async = true,
    format_on_save = false,
    lsp = {},
}

---@param opts Config
---@return Config
function M.set(opts)
    config = vim.tbl_extend('force', config, opts or {})
    return config
end

---@alias config_key "filetype" | "format_async"
---@param key config_key
---@return Config | table<string, fun(): FiletypeConfig> | boolean
function M.get(key)
    if key and config[key] ~= nil then
        return config[key]
    end
    return config
end

---@param conf string
---@return FiletypeConfig
local function string_config(conf)
    local split = vim.split(conf, ' ')
    return {
        exe = split[1],
        args = { unpack(split, 2, #split) },
    }
end

local function parse_configs(f)
    if type(f) == 'function' then
        return parse_configs(f())
    elseif type(f) == 'string' then
        return string_config(f)
    else
        return f
    end
end

---@param ft string
---@return table<FiletypeConfig> | nil
function M.get_ft_configs(ft)
    local f = M.get('filetype')[ft]
    if not f then
        return nil
    end
    if type(f) == 'table' then
        local confs = {}
        for _, c in pairs(f) do
            confs[#confs + 1] = parse_configs(c)
        end
        return confs
    end
    return { parse_configs(f) }
end

return M
