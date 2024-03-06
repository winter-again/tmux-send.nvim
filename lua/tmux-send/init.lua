local Path = require('plenary.path')
-- local scan = require('plenary.scandir')
-- local uv = vim.uv
local M = {}

-- TODO: fig out best way to pass around the same, constant pane ID upon
-- pane its creation? or just how to manage the target pane even if other ones created, whether by plugin
-- or user interacting directly w/ tmux
--
-- TODO: allow -L or -S config ?

M.__target_pane = nil
M.__venv_cmd = 'source ./.venv/bin/activate'

---Checks that target pane is in M and that the target pane itself actually exists
---@return boolean
local function target_pane_exists()
    local panes = M.get_panes()
    if M.__target_pane ~= nil and vim.tbl_contains(panes, M.__target_pane) then
        return true
    end
    return false
end

---@return nil
local function activate_venv()
    -- NOTE: the problem with calling "pipenv shell" is that it runs
    -- a source command on the next line which I think consumes the
    -- immediately following tmux send-keys command somehow
    -- is it fine to just hard code command assuming .venv/bin/activate is desired?
    -- maybe can use plenary.scandir for configuration
    local ft = vim.api.nvim_get_option_value('filetype', { buf = 0 })
    if ft == 'python' then
        -- NOTE: currently not capturing $VIRTUAL_ENV output properly
        -- local venv = vim.fn.system('echo \\$VIRTUAL_ENV')
        -- if venv ~= '' then
        --     print('venv is active')
        -- else
        --     print('venv is inactive')
        M.send_keys(M.__venv_cmd, false) -- venv activation command
    end
end

---@return table
function M.get_panes()
    local cmd = 'tmux list-panes -F "#{pane_id}"'
    local panes = vim.fn.systemlist(cmd)
    if panes ~= '' then
        return panes
    else
        return {}
    end
end

---@return string | nil
function M.create_pane(split_dir, split_pos, pane_size)
    local pane
    if not target_pane_exists() then
        -- TODO: is it worth allowing these args?
        -- when send_keys is called without a split, then it has to create
        -- but then who decides the args for that creation?
        -- maybe better to make this part of config? no need to be this flexible?
        split_dir = split_dir or '-h'
        split_pos = split_pos or '-b'
        pane_size = pane_size or '30%'
        -- -d = don't switch focus
        -- -P = send returned data to stdout
        -- -F = format of returned data
        -- -l = size; could use % too
        -- -b = new pane is to the left or above target-pane
        -- -h = horizontal split (|)
        -- -v = vertical split (-)
        -- -f = new pane spans full window height with -h OR full width with -v
        local cmd = string.format('tmux split-window -dfP %s %s -l %s -F "#{pane_id}"', split_dir, split_pos, pane_size)
        pane = vim.fn.system(cmd)
        -- there's hidden newline char at end of pane_id
        pane = pane:gsub('\n', '')
        M.__target_pane = pane
        return pane
    else
        return M.__target_pane
    end
end

---@return nil
function M.del_pane()
    -- TODO: worth it to also kill any potential REPL running here?
    if target_pane_exists() then
        local cmd = string.format('tmux kill-pane -t %s', M.__target_pane)
        vim.fn.system(cmd)
        M.__target_pane = nil
        -- else
        --     print("Target pane doesn't exist")
    end
end

---@param keys string
---@param cmd_mode boolean
---@return nil
function M.send_keys(keys, cmd_mode)
    cmd_mode = cmd_mode or false
    -- TODO: prob shouldn't handle the check here? make the func that calls this check
    local cmd
    if cmd_mode == false then
        -- need "" around %s for keys so tmux doesn't consume the spaces
        cmd = string.format('tmux send-keys -t %s "%s" Enter', M.__target_pane, keys)
    else
        cmd = string.format('tmux send-keys -t %s %s', M.__target_pane, keys)
    end
    vim.fn.system(cmd)
end

---@return nil
function M.start_repl()
    if not target_pane_exists() then
        -- print('Creating target pane')
        local pane = M.create_pane()
    end

    local repl_cmd
    local ft = vim.api.nvim_get_option_value('filetype', { buf = 0 })
    -- TODO: check first for python venv? if renv, check that it initialized?
    if ft == 'python' then
        repl_cmd = 'python3'
    elseif ft == 'r' then
        repl_cmd = 'R'
    end
    M.send_keys(repl_cmd, false)
end

---@return nil
function M.stop_repl()
    local ft = vim.api.nvim_get_option_value('filetype', { buf = 0 })
    if target_pane_exists() then
        if ft == 'python' or ft == 'r' then
            M.send_keys('C-d', true) -- better to send this?
            -- M.send_keys('exit()', false) -- better to send this ?
            -- elseif ft == 'r' then
            --     M.send_keys('q()', false)
        end
        -- else
        --     print("Target pane doesn't exist")
    end
end

---@param args table | nil
---@return nil
function M.run_curr_buf(args)
    args = args or {}
    -- TODO: ok to use rel path like this?
    if not target_pane_exists() then
        -- print('Creating target pane')
        local pane = M.create_pane()
    end

    local ft = vim.api.nvim_get_option_value('filetype', { buf = 0 })
    local buf_rel = Path:new(vim.api.nvim_buf_get_name(0)):make_relative()

    -- TODO: fig out why scripts with non standard packages still run
    -- as if they're installed w/o virtual env active
    -- the created target_pane seems to ahve the right packages
    -- manually created panes don't
    -- both show same pipenv graph output
    -- print(string.format('Running this script: %s', buf_rel))
    local keys
    if vim.tbl_isempty(args) then
        if ft == 'python' then
            keys = string.format('python3 %s', buf_rel)
        elseif ft == 'r' then
            keys = string.format('Rscript %s', buf_rel)
        end
    else
        -- unpack the args and just pass them with spaces between
        local args_str = table.concat(args, ' ')
        if ft == 'python' then
            keys = string.format('python3 %s %s', buf_rel, args_str)
        elseif ft == 'r' then
            keys = string.format('Rscript %s %s', buf_rel, args_str)
        end
    end

    activate_venv()
    M.send_keys(keys, false) -- this doesn't get run if active_venv() run just before...
end

-- vim.cmd('messages clear')
-- M.send_keys('echo hi, mom')
-- local out = M.get_panes()
-- print(vim.inspect(out))
-- vim.cmd('sleep 2')
-- M.del_pane()

---Setup func
---@param config table | nil
function M.setup(config)
    local default_config = {}
    M.config = vim.tbl_deep_extend('force', default_config, config or {})
    -- vim.api.nvim_create_user_command('Transparent', function()
    --     Transp()
    -- end, { desc = 'Make nvim transparent' })
end

return M
