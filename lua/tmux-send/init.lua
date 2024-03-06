local M = {}

-- TODO: fig out best way to pass around the same, constant pane ID upon
-- pane creation
M._target_pane = nil

function M.list_panes()
    -- -F = format of returned data
    -- local panes = {} -- pane_id values are like "%4"
    -- vim.fn.systemlist() is like system() but returns list
    local pane_ids
    vim.fn.jobwait({
        vim.fn.jobstart({ 'tmux', 'list-panes', '-F', '#{pane_id}' }, {
            stdout_buffered = true,
            on_stdout = function(_, data)
                if data then
                    pane_ids = data
                end
            end,
        }),
    })
    return pane_ids
end

function M.split_window()
    local pane
    if target_pane == nil then
        -- -d = don't switch focus
        -- -P = send returned data to stdout
        -- -F = format of returned data
        -- vim.fn.jobwait({
        vim.fn.jobstart({ 'tmux', 'split-window', '-dhfPb', '-l', '70', '-F', '#{pane_id}' }, {
            stdout_buffered = true,
            on_stdout = function(_, data)
                if data then
                    for _, res in ipairs(data) do
                        if res ~= '' then
                            pane = res
                            break
                        end
                    end
                end
            end,
            on_exit = function(_, _)
                -- NOTE: suggestion
                -- if pane then
                --     do_something_with_pane(pane)
                -- end
                -- we know pane has been assigned here
                target_pane = pane
                print('Target pane created ->', pane)
            end,
        })
        -- })
    else
        pane = target_pane
        print('Created target pane ->', target_pane)
    end
    return pane
end

function M.send_keys(cmd)
    if target_pane == nil then
        print('No pane yet. Making it...')
        target_pane = split_pane()
        -- target_pane = plenary_split_pane()
    else
        print('Pane already exists ->', target_pane)
    end

    -- could think of other alts to target word like right, left, below, etc
    -- good, but there's weird partial line stuff with "%" in zsh
    -- maybe b/c prompt renders too slow before we send the command?
    -- goes away when I DONT export TERM=wezterm in zshrc
    vim.fn.jobstart({ 'tmux', 'send-keys', '-t', target_pane, cmd, 'ENTER' })
end

---Setup func
---@param config table | nil
function M.setup(config)
    local default_config = {}
    M.config = vim.tbl_deep_extend('force', default_config, config or {})
end

return M
