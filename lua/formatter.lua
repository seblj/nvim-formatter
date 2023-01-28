local config = require('formatter.config')
local util = require('formatter.util')
local Format = require('formatter.format')

local M = {}

---@param opts Config | nil
function M.setup(opts)
    opts = opts or {}
    config.set(opts)

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
                Format:new(c_opts.line1, c_opts.line2, write):run('all')
            else
                Format:new(c_opts.line1, c_opts.line2, write):run(c_opts.args)
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
