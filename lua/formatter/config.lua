local M = {}

---@class Config
---@field filetype table<string, fun(): FiletypeConfig> | string | table<string>
---@field format_async boolean
---@field format_on_save boolean | fun(): boolean

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
}
local ft_config = {}

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

---@param conf table<string> | FiletypeConfig
---@return FiletypeConfig
local function table_config(conf)
    -- Assume the table is already structured
    if conf.exe then
        return conf
    else
        return {
            exe = conf[1],
            args = { unpack(conf, 2) },
        }
    end
end

---@param ft string
---@return FiletypeConfig | nil
function M.get_ft_config(ft)
    local f = M.get('filetype')[ft]
    if ft_config[ft] then
        return ft_config[ft]
    end
    if f then
        local conf
        if type(f) == 'string' then
            conf = string_config(f)
        elseif type(f) == 'table' then
            conf = table_config(f)
        else
            conf = f()
        end
        ft_config[ft] = conf
        return conf
    else
        return nil
    end
end

return M
