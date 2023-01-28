# nvim-formatter

Formatter with treesitter integration

## Install

Using your package manager of choice

```lua
require('lazy').setup({
    { 'seblj/nvim-formatter' },
    { 'nvim-lua/plenary.nvim' },
})
```

### Configure

Each formatter should return a function that returns a table that consist of:

| Key                   | Type               | Meaning                                                                                                       |
| --------------------- | ------------------ | ------------------------------------------------------------------------------------------------------------- |
| `exe`                 | string             | Executable to run                                                                                             |
| `cond`                | function?          | Returns a boolean whether to format or not                                                                    |
| `args`                | table?             | Table of args to pass                                                                                         |
| `cwd`                 | string?            | The path to run the program from                                                                              |
| `disable_as_injected` | (string or table)? | Avoids formatting as an injected language with treesitter.<br/> Table of filetypes or a `*` for all filetypes |
| `disable_injected`    | (string or table)? | Avoids formatting injected languages with treesitter.<br/> Table of filetypes or a `*` for all filetypes      |

### Example:

```lua
require('formatter').setup({
    filetype = {
        lua = function()
            return {
                exe = 'stylua',
                args = { '--search-parent-directories', '--stdin-filepath', vim.api.nvim_buf_get_name(0), '-' },
            }
        end,
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

To enable format on save, you can create an `autocmd` to trigger `FormatWrite`.

Note that it uses `BufWritePost` and not `BufWritePre`. This is necessary when
formatting asynchronously to not trigger a buffer change. `nvim-formatter` will
re-save the buffer after inserting new changes. If you format it synchronously
by setting `format_async = false` you may change `BufWritePost` to `BufWritePre`.
You can also then change `FormatWrite` to `Format`. See the section about
exposed commands

Formatting on save with `format_async = true` will _not_ break `:wq` if you use
`FormatWrite`. `nvim-formatter` sets an autocmd on `ExitPre` to make sure that
the buffer is formatted before quitting. However, if the formatter can't finish
in 5 seconds, it will timeout, exit and _not_ format the buffer

```lua
vim.api.nvim_create_autocmd('BufWritePost', {
    group = vim.api.nvim_create_augroup('FormatOnWrite', { clear = true }),
    pattern = '*.lua',
    callback = function()
        vim.cmd.FormatWrite()
    end,
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
