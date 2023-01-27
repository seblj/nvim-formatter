# nvim-formatter

Formatter with treesitter integration

Huge thanks to [`formatter.nvim`](https://github.com/mhartington/formatter.nvim)
for initial inspiration

## Install

Using your package manager of choice

#### Example:

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

#### Example:

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

By default nvim-formatter will format the buffer async and not block the editor.
When the result from the formatter comes back, it only inserts the changes if
there hasn't been any changes in the buffer while it was running the formatter.

If you however wish to run it synchronously, you can set an options like:

```lua
require('formatter').setup({
    format_async = false,
})
```

Note that it does also work on `:wq` even with `format_async = true`.
`nvim-formatter` sets an autocmd on `ExitPre` to make sure that the buffer is
formatted before quitting. However, if the formatter can't finish in 5 seconds,
it will timeout, exit and _not_ format the buffer

### Format on save

To enable format on save, you can create an `autocmd` to trigger `Format`.

Note that it uses `BufWritePost` and not `BufWritePre`. This is necessary when
formatting asynchronously to not trigger a buffer change. `nvim-formatter` will
re-save the buffer after inserting new changes. If you format it synchronously
by setting `format_async = false` you may change `BufWritePost` to `BufWritePre`.

```lua
vim.api.nvim_create_autocmd('BufWritePost', {
    group = vim.api.nvim_create_augroup('FormatOnWrite', { clear = true }),
    pattern = '*.lua',
    callback = function()
        vim.cmd.Format()
    end,
})
```

### Exposed commands

- `Format`: Formats everything in the buffer including injections
- `FormatInjections`: Formats only treesitter injected languages
- `FormatBasic`: Format buffer excluding treesitter injections
