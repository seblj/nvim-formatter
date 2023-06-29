# nvim-formatter

Formatter with treesitter integration

## Requirements

- Neovim 0.9

## Install

Using your package manager of choice

```lua
require('lazy').setup({
    { 'seblj/nvim-formatter' },
})
```

### Configure

To configure you need to set it up with each key in the table being the
filetype, and the value being a `string`. You can use `string.format()` to do
more advanced arguments.

However, if you want even more control, you can also create a function that
returns either a string or a table with the following keys.

| Key                   | Type               | Meaning                                                                                                       |
| --------------------- | ------------------ | ------------------------------------------------------------------------------------------------------------- |
| `exe`                 | string             | Executable to run                                                                                             |
| `cond`                | function?          | Returns a boolean whether to format or not                                                                    |
| `args`                | table?             | Table of args to pass                                                                                         |
| `cwd`                 | string?            | The path to run the program from                                                                              |
| `disable_as_injected` | (string or table)? | Avoids formatting as an injected language with treesitter.<br/> Table of filetypes or a `*` for all filetypes |
| `disable_injected`    | (string or table)? | Avoids formatting injected languages with treesitter.<br/> Table of filetypes or a `*` for all filetypes      |

### Examples:

```lua
require('formatter').setup({
    filetype = {
        -- Returns a function that will run the first time it is formatting
        lua = function()
            return {
                exe = 'stylua',
                args = { '--search-parent-directories', '--stdin-filepath', vim.api.nvim_buf_get_name(0), '-' },
            }
        end,
        -- Assumes this is `exe`
        go = 'goimports',
        -- Will split on spaces and assumes the first is `exe` and rest is `args`
        rust = 'rustfmt --edition 2021',
    },
})
```

### Multiple formatters per filetype

If you like to run multiple formatters per filetype, the value of a filetype
could be a table of formatters. This runs stylua first, then runs luafmt. Note
that you probably do NOT want to run multiple formatters. I implemented this
specifically for my own purpose of wanting to format
[`leptos`](https://github.com/leptos-rs/leptos) in Rust using
[`leptosfmt`](https://github.com/bram209/leptosfmt) while still also format
using [`rustfmt`](https://github.com/rust-lang/rustfmt)

```lua
require('formatter').setup({
    filetype = {
        -- Two formatters, and both configured as strings
        lua = {
            'stylua --search-parent-directories -',
            'luafmt --stdin',
        },

        -- Two formatters where one is configured as a function and the other as
        -- a string
        lua = {
            'stylua --search-parent-directories -',
            function()
                return 'luafmt --stdin'
            end,
        },
    },
})
```

### Notes:

By default `nvim-formatter` will format the buffer async and not block the editor.
When the result from the formatter comes back, it only inserts the changes if
there hasn't been any changes in the buffer while it was running the formatter.

If you however wish to run it synchronously, you can turn it off with:

```lua
require('formatter').setup({
    format_async = false,
})
```

### Format on save

To enable format on save, you can set an option `format_on_save` to true or a
function that returns a boolean. This options is set to false by default. If it
is a function, it will only format on save if the function returns true.

For example, you can have a buffer variable that can toggle formatting on save
on and off with:

```lua
vim.keymap.set('n', '<leader>tf', function()
    vim.b.disable_formatting = not vim.b.disable_formatting
    if vim.b.disable_formatting then
        vim.api.nvim_echo({ { 'Disabled autoformat on save' } }, false, {})
    else
        vim.api.nvim_echo({ { 'Enabled autoformat on save' } }, false, {})
    end
end, { desc = 'Format: Toggle format on save' })
```

You can then setup `nvim-formatter` like this

```lua
require('formatter').setup({
    format_on_save = function()
        return not vim.b.disable_formatting
    end,
})
```

As `nvim-formatter` is a formatter plugin, it is also able to setup
`format_on_save` for language servers. It accepts a list of language server
names. If `format_on_save` is setup, and a list of language server names is
used, then it will format on save using `vim.lsp.buf.format()` if the language
server is attached to the buffer, and `format_on_save` either is true or
resolves to true through a function.

```lua
require('formatter').setup({
    format_on_save = function()
        return not vim.b.disable_formatting
    end,
    lsp = { 'rust_analyzer' },
})
```

### Exposed commands

- `Format`: Formats everything in the buffer including injections
- `FormatWrite`: Same as `Format` but sets an autocmd on `ExitPre` to format
  before `:wq`. Meant to be used with format on save when `format_async = true`

In addition to this, both commands is able to take an argument of either `basic`
or `injections`.

- `basic` will only format the buffer _excluding_ treesitter injections.
- `injections` will _only_ format the injections in the buffer

## Acknowledgement

Huge thanks to [`formatter.nvim`](https://github.com/mhartington/formatter.nvim)
for initial inspiration
