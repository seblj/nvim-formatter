local config = require('formatter.config')
local Format = require('formatter.format')

local M = {}

function M.setup(opts)
    opts = opts or {}
    config.set(opts)

    vim.api.nvim_create_user_command('Format', function(c_opts)
        Format:new(c_opts.line1, c_opts.line2):run('all')
    end, {
        range = '%',
        bar = true,
    })

    vim.api.nvim_create_user_command('FormatWrite', function(c_opts)
        Format:new(c_opts.line1, c_opts.line2):run('all', true)
    end, {
        range = '%',
        bar = true,
    })

    vim.api.nvim_create_user_command('FormatInjections', function(c_opts)
        Format:new(c_opts.line1, c_opts.line2, true):run('injections')
    end, {
        bar = true,
        range = '%',
    })

    vim.api.nvim_create_user_command('FormatInjectionsWrite', function(c_opts)
        Format:new(c_opts.line1, c_opts.line2, true):run('injections')
    end, {
        bar = true,
        range = '%',
    })

    vim.api.nvim_create_user_command('FormatBasic', function(c_opts)
        Format:new(c_opts.line1, c_opts.line2):run('basic')
    end, {
        bar = true,
        range = '%',
    })

    vim.api.nvim_create_user_command('FormatBasicWrite', function(c_opts)
        Format:new(c_opts.line1, c_opts.line2):run('basic', true)
    end, {
        bar = true,
        range = '%',
    })
end

return M
