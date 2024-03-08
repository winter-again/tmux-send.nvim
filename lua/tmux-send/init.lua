local Path = require('plenary.path')
-- local scan = require('plenary.scandir')
local M = {}

-- TODO: allow -L or -S config ?
-- NOTE: {last} lets you target last pane
M.__target_pane = nil
M.__venv_cmd = 'source ./.venv/bin/activate'

---Checks that target pane is in M and that the target pane itself actually exists
---@return boolean
local function target_pane_exists()
    local panes = M.get_panes()
    if M.__target_pane ~= nil and vim.tbl_contains(panes, M.__target_pane) then
        return true
    else
        M.__target_pane = nil
        return false
    end
end

---@return nil
local function activate_venv()
    if target_pane_exists() then
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
function M.delete_pane()
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
    -- TODO: prob shouldn't handle the checking for pane here? make the func that calls this check?
    -- alternatively the check occurs here and then it's just a single point of checking?
    -- and simply print error or message if the target pane doesn't exist?

    -- TODO: need to figure out all the string esc; eventually can be its own func
    -- are there any other problematic keys?
    -- look at vim.api.nvim_replace_termcodes()
    keys = keys:gsub('"', '\\"')
    local cmd
    if cmd_mode == false then
        -- need "" around %s for keys so tmux doesn't consume the spaces
        cmd = string.format('tmux send-keys -t %s "%s" Enter', M.__target_pane, keys)
    else
        cmd = string.format('tmux send-keys -t %s %s', M.__target_pane, keys)
    end
    -- print(cmd)
    vim.fn.system(cmd)
end

---@return nil
function M.start_repl()
    -- TODO: need to check if REPL already exists? is even possible?
    if not target_pane_exists() then
        local pane = M.create_pane()
    end

    local repl_cmd
    local ft = vim.api.nvim_get_option_value('filetype', { buf = 0 })
    -- TODO: check first for python venv?
    -- for R, can look for renv dir and the activate.R script?
    if ft == 'python' then
        activate_venv()
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
        -- TODO: do we really need to make this lang specific? maybe should just kill the pane in general...
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

---@return nil
function M.send_curr_line()
    if target_pane_exists() then
        local line = vim.api.nvim_get_current_line()
        M.send_keys(line, false)
        -- TODO: after selection is sent, leave visual line mode?
        -- optionally can highlight the lines? italics?
    end
end

---@return nil
function M.send_vis_sel()
    local _, ls, cs = unpack(vim.fn.getpos('v'))
    local _, le, ce = unpack(vim.fn.getpos('.'))
    -- TODO: this returns table of each line in the vis sel
    -- only works with whole lines, which I think is pref
    local lines = vim.api.nvim_buf_get_lines(0, ls - 1, le, true)
    -- TODO: figure out how to execute lines
    -- for something like a func defn or for loop that spans multiple lines
    -- is just adding a final '\n' sufficient?
    lines = table.concat(lines, '\n') .. '\n'
    M.send_keys(lines, false)
    -- TODO: read more about these 2 funcs
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'x', true)
end

vim.keymap.set('v', '<leader>ss', function()
    M.send_vis_sel()
end)

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
        -- TODO: maybe it's easier from user pov to just pass a single string of the
        -- args rather than in table form?
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

---Setup func
---@param config table | nil
function M.setup(config)
    local default_config = {}
    M.config = vim.tbl_deep_extend('force', default_config, config or {})

    -- wrap into a single user command with each sub command as args with completion?
    -- how to pass additional args to something like M.create_pane()?
    vim.api.nvim_create_user_command('TmuxCreate', function(opts)
        local cmd = tostring(opts.fargs[1])
        if cmd == 'get_panes' then
            print(vim.inspect(M.get_panes()))
        elseif cmd == 'create_pane' then
            M.create_pane()
        elseif cmd == 'delete_pane' then
            M.delete_pane()
        elseif cmd == 'run_buf' then
            M.run_curr_buf()
        end
    end, {
        nargs = 1,
        complete = function(ArgLead, CmdLine, CursorPos)
            return {
                'get_panes',
                'create_pane',
                'delete_pane',
                'run_buf',
            }
        end,
        desc = 'Tmux interaction',
    })
    -- vim.api.nvim_create_user_command('Bg', function(opts)
    --     local bg_profile = tostring(opts.fargs[1])
    --     wezterm_config.set_wezterm_user_var('profile_background', bg_profile)
    -- end, {
    --     nargs = 1,
    --     complete = function(ArgLead, CmdLine, CursorPos)
    --         local bg_names = {}
    --         for name, _ in pairs(profile_data.background) do
    --             table.insert(bg_names, name)
    --         end
    --         table.sort(bg_names)
    --         return bg_names
    --     end,
    --     desc = 'Set Wezterm background',
    -- })
end

return M
