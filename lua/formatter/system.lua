-- Use the implementation from this PR
-- https://github.com/neovim/neovim/pull/23827/files
-- Remove once merged an in an official release

local uv = vim.loop

--- @param spec string[]|SystemSpec
--- @return SystemSpec
local function process_spec(spec)
    if spec[1] then
        local cmd = {} --- @type string[]
        for _, p in ipairs(spec) do
            cmd[#cmd + 1] = p
        end
        spec = vim.deepcopy(spec)
        spec.cmd = cmd
    end

    return spec
end

---@private
---@param output uv_stream_t|function|'false'
---@return uv_stream_t?
---@return function? Handler
---@return boolean: Use handler
local function setup_output(output)
    if output == nil then
        return assert(uv.new_pipe(false)), nil, true
    end

    if type(output) == 'function' then
        return assert(uv.new_pipe(false)), output, true
    end

    if output == false then
        return nil, nil, false
    end

    --- @cast output uv_stream_t

    -- output must be uv_stream_t
    return output, nil, false
end

---@private
---@param input uv_stream_t|string|string[]|nil
---@return uv_stream_t?
---@return string|string[]?
local function setup_input(input)
    if type(input) == 'string' or type(input) == 'table' then
        return assert(uv.new_pipe(false)), input
    end

    -- output must be uv_stream_t
    return input, nil
end

--- @param cmd string|string[]
--- @param args? string[]
--- @return string Command
--- @return string[]? Arguments
local function setup_cmd(cmd, args)
    if type(cmd) == 'string' then
        cmd = { cmd }
        if args then
            vim.list_extend(cmd, args)
        end
    end

    return cmd[1], vim.list_slice(cmd, 2)
end

--- uv.spawn will completely overwrite the environment
--- when we just want to modify the existing one, so if env is provided
--- make sure to prepopulate it with the current env.
--- @param env table<string,string|number>
--- @return string[]?
local function setup_env(env)
    if not env then
        return
    end

    --- @type table<string,string>
    local env0 = vim.tbl_extend('force', vim.fn.environ(), env)

    local renv = {} --- @type string[]
    for k, v in pairs(env0) do
        renv[#renv + 1] = string.format('%s=%s', k, tostring(v))
    end

    return renv
end

---@private
---@param pipe uv_stream_t
---@param input? string|string[]
local function handle_input(pipe, input)
    if type(input) == 'table' then
        for _, v in ipairs(input) do
            pipe:write(v)
            pipe:write('\n')
        end
    elseif type(input) == 'string' then
        pipe:write(input)
    end

    -- Shutdown the write side of the duplex stream and then close the pipe.
    -- Note shutdown will wait for all the pending write requests to complete
    -- TODO(lewis6991): apparently shutdown doesn't behave this way.
    -- (https://github.com/neovim/neovim/pull/17620#discussion_r820775616)
    pipe:write('', function()
        pipe:shutdown(function()
            if pipe then
                pipe:close()
            end
        end)
    end)
end

---@private
---@param pipe uv_stream_t
---@param handler? function
---@param output string[]
local function handle_output(pipe, handler, output)
    if handler then
        pipe:read_start(handler)
    else
        pipe:read_start(function(err, data)
            if err then
                error(err)
            end
            output[#output + 1] = data
        end)
    end
end

---@private
---@param handles uv_handle_t[]
local function close_handles(handles)
    for _, handle in pairs(handles) do
        if not handle:is_closing() then
            handle:close()
        end
    end
end

--- @class SystemSpec
--- @field cmd string|string[]
--- @field args? string[]
--- @field stdin string|string[]|uv_stream_t
--- @field stdout uv_stream_t|fun(err:string, data: string)|'false'
--- @field stderr uv_stream_t|fun(err:string, data: string)|'false'
--- @field cwd? string
--- @field env? table<string,string|number>
--- @field timeout? integer Timeout in ms
--- @field detached? boolean
---
--- @class SystemOut
--- @field code integer
--- @field signal integer
--- @field stdout? string
--- @field stderr? string

--- Run a system command
---
--- @param user_spec string[]|SystemSpec
--- @param on_exit fun(out: SystemOut)|nil
--- @return uv_process_t|nil, integer|string process handle and PID
--- @overload fun(user_spec: string[]|SystemSpec): SystemOut
local function run(user_spec, on_exit)
    vim.validate({
        user_spec = { user_spec, 'table' },
        on_exit = { on_exit, 'function', true },
    })

    local spec = process_spec(user_spec)

    local stdout, stdout_handler, handle_stdout = setup_output(spec.stdout)
    local stderr, stderr_handler, handle_stderr = setup_output(spec.stderr)
    local stdin, input = setup_input(spec.stdin)
    local cmd, args = setup_cmd(spec.cmd, spec.args)

    -- Pipes which are being automatically managed.
    -- Don't manage if pipe was passed directly in spec
    local pipes = {} --- @type uv_handle_t[]

    if input then
        pipes[#pipes + 1] = stdin
    end

    if handle_stdout then
        pipes[#pipes + 1] = stdout
    end

    if handle_stderr then
        pipes[#pipes + 1] = stderr
    end

    -- Define data buckets as tables and concatenate the elements at the end as
    -- one operation.
    --- @type string[], string[]
    local stdout_data, stderr_data

    local done = false
    local out --- @type SystemOut

    local handle, pid
    handle, pid = uv.spawn(cmd, {
        args = args,
        stdio = { stdin, stdout, stderr },
        cwd = spec.cwd,
        env = setup_env(spec.env),
        detached = spec.detached,
    }, function(code, signal)
        close_handles(pipes)
        if handle then
            handle:close()
        end
        done = true

        local ret = {
            code = code,
            signal = signal,
            stdout = stdout_data and table.concat(stdout_data) or nil,
            stderr = stderr_data and table.concat(stderr_data) or nil,
        }

        if on_exit then
            on_exit(ret)
        else
            out = ret
        end
    end)

    if not handle then
        close_handles(pipes)
        error(pid)
    end

    if stdout and handle_stdout then
        stdout_data = {}
        handle_output(stdout, stdout_handler, stdout_data)
    end

    if stderr and handle_stderr then
        stderr_data = {}
        handle_output(stderr, stderr_handler, stderr_data)
    end

    if input then
        handle_input(assert(stdin), input)
    end

    if on_exit then
        -- TODO(lewis6991): implement timeout for async
        return handle, pid
    end

    vim.wait(spec.timeout or 10000, function()
        return done
    end)

    if not done then
        if handle then
            close_handles(pipes)
            handle:close()
        end

        local cmd_str = cmd .. ' ' .. table.concat(args or {}, ' ')
        error(string.format('System command timed out: %s', cmd_str))
    end

    return out
end

if not vim.system then
    vim.system = run
end
