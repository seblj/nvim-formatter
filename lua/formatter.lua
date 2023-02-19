local config = require('formatter.config')
local util = require('formatter.util')
local Format = require('formatter.format')

local M = {}

---@param opts Config | nil
function M.setup(opts)
    opts = opts or {}
    config.set(opts)

    if opts.format_on_save then
        vim.api.nvim_create_autocmd('FileType', {
            pattern = vim.tbl_keys(opts.filetype),
            group = vim.api.nvim_create_augroup('nvim-formatter_on_save_ft', { clear = true }),
            callback = function()
                vim.api.nvim_create_autocmd('BufWritePost', {
                    buffer = 0,
                    group = vim.api.nvim_create_augroup('nvim-formatter_on_save_buf', { clear = true }),
                    callback = function()
                        if type(opts.format_on_save) == 'function' then
                            if opts.format_on_save() then
                                vim.cmd.FormatWrite()
                            end
                        else
                            vim.cmd.FormatWrite()
                        end
                    end,
                })
            end,
        })
    end

    local arguments = { 'basic', 'injections' }

    ---@param arg_lead string
    local function command_completion(arg_lead)
        return vim.tbl_filter(function(item)
            return vim.startswith(item, arg_lead)
        end, arguments)
    end

    ---@param cmd string
    ---@param write boolean
    local function create_command(cmd, write)
        vim.api.nvim_create_user_command(cmd, function(c_opts)
            if c_opts.args ~= '' and not vim.tbl_contains(arguments, c_opts.args) then
                return vim.notify(
                    string.format('%s %s is not a valid command', cmd, c_opts.args),
                    vim.log.levels.ERROR,
                    util.notify_opts
                )
            end

            if c_opts.args == '' then
                Format:new(c_opts.line1, c_opts.line2):run('all', write)
            else
                Format:new(c_opts.line1, c_opts.line2):run(c_opts.args, write)
            end
        end, {
            complete = command_completion,
            nargs = '?',
            range = '%',
            bar = true,
        })
    end

    create_command('Format', false)
    create_command('FormatWrite', true)
end

return M
