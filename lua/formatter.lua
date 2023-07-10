local config = require('formatter.config')
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
                local bufnr = vim.api.nvim_get_current_buf()
                vim.api.nvim_create_autocmd('BufWritePost', {
                    buffer = 0,
                    group = vim.api.nvim_create_augroup(
                        string.format('nvim-formatter_on_save_buf_%s', bufnr),
                        { clear = true }
                    ),
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

        if opts.lsp then
            vim.api.nvim_create_autocmd('LspAttach', {
                callback = function(args)
                    local client = vim.lsp.get_client_by_id(args.data.client_id)
                    if vim.tbl_contains(opts.lsp, client.name) then
                        vim.api.nvim_create_autocmd('BufWritePre', {
                            group = vim.api.nvim_create_augroup(
                                string.format('nvim-formatter_lsp_on_save_buf_%s', args.buf),
                                { clear = true }
                            ),
                            buffer = args.buf,
                            callback = function()
                                if type(opts.format_on_save) == 'function' then
                                    if opts.format_on_save() then
                                        vim.lsp.buf.format()
                                    end
                                else
                                    vim.lsp.buf.format()
                                end
                            end,
                            desc = 'nvim-formatter lsp formatting',
                        })
                    end
                end,
            })
        end
    end

    local arguments = { 'basic', 'injections' }
    local function parse_cmdline(args)
        return vim.tbl_filter(function(item)
            return item ~= ''
        end, vim.split(args, ' '))
    end

    ---@param arg_lead string
    local function command_completion(arg_lead, cmdline)
        local args = parse_cmdline(cmdline)
        if vim.tbl_contains(arguments, args[2]) then
            return
        end

        return vim.tbl_filter(function(item)
            return vim.startswith(item, arg_lead)
        end, arguments)
    end

    -- Parse args as path if #args is higher than treshold. Otherwise, use
    -- globpath
    local function parse_paths(args, treshold)
        return #args > treshold
                and vim.tbl_map(function(value)
                    return vim.fn.fnamemodify(value, ':p')
                end, args)
            or vim.tbl_filter(function(item)
                return item ~= ''
            end, vim.split(vim.fn.globpath(vim.fn.getcwd(), args[2] or args[1]), '\n'))
    end

    ---@param cmd string
    ---@param write boolean
    local function create_command(cmd, write, async)
        vim.api.nvim_create_user_command(cmd, function(c_opts)
            local args = parse_cmdline(c_opts.args)
            local range = c_opts.range ~= 0 and { c_opts.line1, c_opts.line2 }

            -- Format regular if no arguments or the only argument is either
            -- "basic" or "injections"
            if vim.tbl_isempty(args) or (vim.tbl_contains(arguments, args[1]) and #args < 2) then
                local type = vim.tbl_isempty(args) and 'all' or args[1]
                Format:new(range, async):start(type, write)
            else
                local paths, type
                -- If there are more than two arguments and no "basic",
                -- or "injections", it means that a list of files is added as
                -- arguments to format
                if vim.tbl_contains(arguments, args[1]) then
                    type = table.remove(args, 1)
                    -- If there are more than two arguments, then assume it is a
                    -- list of files. Otherwise, treat it as glob
                    paths = parse_paths(args, 2)
                else
                    -- Since the first argument is not "basic", or
                    -- "injections" we only check if number of arguments is
                    -- larger than one.
                    type = 'all'
                    paths = parse_paths(args, 1)
                end

                for _, path in ipairs(paths) do
                    vim.api.nvim_create_autocmd('BufAdd', {
                        once = true,
                        pattern = path,
                        callback = function(a)
                            vim.api.nvim_buf_call(a.buf, function()
                                vim.cmd.filetype('detect')
                            end)
                            Format:new(range, async, a.buf):start(type, write)
                        end,
                    })
                    vim.cmd.badd(path)
                end
            end
        end, {
            complete = command_completion,
            nargs = '?',
            range = '%',
            bar = true,
        })
    end

    create_command('Format', false, true)
    create_command('FormatWrite', true, true)
    create_command('FormatSync', false, false)
end

return M
