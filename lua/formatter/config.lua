local M = {}

---@class Config
---@field filetype table<string, string | table<string> | fun(): FiletypeConfig>
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
local buffer_config = {}

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
    if not f then
        return nil
    end
    if type(f) == 'function' then
        local bufnr = vim.api.nvim_get_current_buf()
        -- Cache per ft in the buffer
        if buffer_config[bufnr] and buffer_config[bufnr][ft] then
            return buffer_config[bufnr][ft]
        end
        local conf = f()
        if not buffer_config[bufnr] then
            buffer_config[bufnr] = {}
        end
        buffer_config[bufnr][ft] = conf
        return conf
    elseif type(f) == 'table' then
        return table_config(f)
    else
        return string_config(f)
    end
end

return M
