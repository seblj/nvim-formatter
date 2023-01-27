local M = {}

---@class Config
---@field filetype table<string, fun(): FiletypeConfig>
---@field async boolean

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

---@param ft string
---@return FiletypeConfig | nil
function M.get_ft_config(ft)
    local f = M.get('filetype')[ft]
    if ft_config[ft] then
        return ft_config[ft]
    end
    if f then
        local conf = f()
        ft_config[ft] = conf
        return conf
    else
        return nil
    end
end

return M
