local config = require('formatter.config')
local Format = require('formatter.format')

local M = {}

---@param opts Config | nil
function M.setup(opts)
    opts = opts or {}
    config.set(opts)

    ---@param bufnr number
    ---@param event string
    ---@param group string
    ---@param method function
    local function setup_autocmd(bufnr, event, group, method)
        vim.api.nvim_create_autocmd(event, {
            buffer = bufnr,
            group = vim.api.nvim_create_augroup(group, { clear = true }),
            callback = function()
                if type(opts.format_on_save) == 'function' then
                    if opts.format_on_save() then
                        method()
                    end
                else
                    method()
                end
            end,
        })
    end

    if opts.format_on_save then
        vim.api.nvim_create_autocmd('FileType', {
            pattern = vim.tbl_keys(opts.filetype),
            group = vim.api.nvim_create_augroup('nvim-formatter_on_save_ft', { clear = true }),
            callback = function()
                local bufnr = vim.api.nvim_get_current_buf()
                local group = string.format('nvim-formatter_on_save_buf_%s', bufnr)
                setup_autocmd(bufnr, 'BufWritePost', group, vim.cmd.Format)
            end,
        })

        if opts.lsp then
            vim.api.nvim_create_autocmd('LspAttach', {
                callback = function(args)
                    local client = vim.lsp.get_client_by_id(args.data.client_id)
                    if client and vim.tbl_contains(opts.lsp, client.name) then
                        local group = string.format('nvim-formatter_lsp_on_save_buf_%s', args.buf)
                        setup_autocmd(args.buf, 'BufWritePre', group, vim.lsp.buf.format)
                    end
                end,
            })
        end
    end

    local arguments = { 'basic', 'injections' }
    local function parse_cmdline(args)
        return vim.iter.filter(function(item)
            return item ~= ''
        end, vim.split(args, ' '))
    end

    ---@param arg_lead string
    local function command_completion(arg_lead, cmdline)
        local args = parse_cmdline(cmdline)
        if vim.tbl_contains(arguments, args[2]) then
            return
        end

        return vim.iter.filter(function(item)
            return vim.startswith(item, arg_lead)
        end, arguments)
    end

    -- Parse args as path if #args is higher than treshold. Otherwise, use
    -- globpath
    local function parse_paths(args, treshold)
        return #args > treshold
                and vim.iter.map(function(value)
                    return vim.fn.fnamemodify(value, ':p')
                end, args)
            or vim.iter.filter(function(item)
                return item ~= ''
            end, vim.split(vim.fn.globpath(vim.fn.getcwd(), args[2] or args[1]), '\n'))
    end

    vim.api.nvim_create_user_command('Format', function(c_opts)
        local args = parse_cmdline(c_opts.args)
        local range = c_opts.range ~= 0 and { c_opts.line1, c_opts.line2 }

        -- Format regular if no arguments or the only argument is either
        -- "basic" or "injections"
        if vim.tbl_isempty(args) or (vim.tbl_contains(arguments, args[1]) and #args < 2) then
            local type = vim.tbl_isempty(args) and 'all' or args[1]
            Format:new(range):start(type)
        else
            local type = vim.iter(arguments):find(args[1]) or 'all'
            local paths = type == 'all' and parse_paths(args, 1) or parse_paths(args, 2)

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

return M
