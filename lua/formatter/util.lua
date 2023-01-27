local parsers = require('nvim-treesitter.parsers')

local util = {}

---Workaround to save and restore marks before calling vim.api.nvim_buf_set_lines
---Ideally I would want to implement a diff that could calculate all the changes
---on lines and characters, and use vim.lsp.util.apply_text_edits
---@param bufnr number
function util.save_marks(bufnr)
    local marks = {}
    for _, m in pairs(vim.fn.getmarklist(bufnr)) do
        if m.mark:match("^'[a-z]$") then
            marks[m.mark] = m.pos
        end
    end
    return marks
end

---@param bufnr number
---@param marks table
function util.restore_marks(bufnr, marks)
    for _, m in pairs(vim.fn.getmarklist(bufnr)) do
        marks[m.mark] = nil
    end

    for mark, pos in pairs(marks) do
        if pos then
            vim.fn.setpos(mark, pos)
        end
    end
end

return util
