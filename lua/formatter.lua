local config = require('formatter.config')
local Format = require('formatter.format')

local M = {}

---@param opts NvimFormatterConfig | nil
function M.setup(opts)
    opts = opts or {}
    config.set(opts)

    if opts.format_on_save then
        vim.api.nvim_create_autocmd('BufWritePost', {
            pattern = '*',
            group = vim.api.nvim_create_augroup('nvim-formatter_on_save_buf', { clear = true }),
            callback = function()
                if type(opts.format_on_save) == 'function' then
                    if opts.format_on_save() then
                        vim.cmd.Format()
                    end
                else
                    vim.cmd.Format()
                end
            end,
        })
    end

    local arguments = { 'basic', 'injections' }
    local function parse_cmdline(args)
        return vim.iter(vim.split(args, ' '))
            :filter(function(item)
                return item ~= ''
            end)
            :totable()
    end

    ---@param arg_lead string
    local function command_completion(arg_lead, cmdline)
        local args = parse_cmdline(cmdline)
        if vim.tbl_contains(arguments, args[2]) then
            return
        end

        return vim.iter(arguments)
            :filter(function(item)
                return vim.startswith(item, arg_lead)
            end)
            :totable()
    end

    local function format(c_opts)
        local args = parse_cmdline(c_opts.args)
        local range = c_opts.range ~= 0 and { c_opts.line1, c_opts.line2 } or nil

        -- Format regular if no arguments or the only argument is either
        -- "basic" or "injections"
        if vim.tbl_isempty(args) or (vim.tbl_contains(arguments, args[1]) and #args < 2) then
            local type = vim.tbl_isempty(args) and 'all' or args[1]
            Format:new(range):start(type)
        else
            local type = vim.iter(arguments):find(args[1]) or 'all'
            ---@diagnostic disable-next-line: param-type-mismatch
            local paths = vim.fn.globpath(vim.uv.cwd(), args[2] or args[1], 0, 1)

            for _, path in ipairs(paths) do
                vim.api.nvim_create_autocmd('BufAdd', {
                    once = true,
                    pattern = path,
                    callback = function(a)
                        vim.api.nvim_buf_call(a.buf, function()
                            vim.cmd.filetype('detect')
                        end)
                        Format:new(range, a.buf):start(type)
                    end,
                })

                local bufnr = vim.fn.bufnr(path)
                if bufnr == -1 then
                    vim.cmd.badd(path)
                else
                    Format:new(range, bufnr):start(type)
                end
            end
        end
    end

    vim.api.nvim_create_user_command('Format', function(c_opts)
        format(c_opts)
    end, {
        complete = command_completion,
        nargs = '?',
        range = '%',
        bar = true,
    })

    -- TODO: Remove at a later time
    local function deprecated_command(command)
        vim.api.nvim_create_user_command(command, function(c_opts)
            vim.notify(
                string.format(
                    '`%s` is deprecated. Use `Format` instead.\n`%s` will be removed at a later time',
                    command,
                    command
                ),
                vim.log.levels.WARN
            )
            format(c_opts)
        end, {
            complete = command_completion,
            nargs = '?',
            range = '%',
            bar = true,
        })
    end

    deprecated_command('FormatWrite')
    deprecated_command('FormatSync')
end

return M
