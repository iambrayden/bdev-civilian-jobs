-- /civjobs admin menu: one click turns a job on or off.

RegisterNetEvent('bdev-civilian-jobs:client:admin', function(list)
    local options = {}
    for _, j in ipairs(list or {}) do
        options[#options + 1] = {
            title = j.label,
            description = ('%s  •  id: %s  •  %d on shift%s'):format(j.enabled and 'ON' or 'OFF', j.id, j.working,
                j.overridden and '  •  set in game' or ''),
            icon = j.enabled and 'toggle-on' or 'toggle-off',
            iconColor = j.enabled and '#16c784' or '#ea3943',
            metadata = { { label = 'Resource', value = j.resource } },
            onSelect = function()
                if j.enabled and j.working > 0 then
                    local confirm = lib.alertDialog({
                        header = 'Turn off ' .. j.label .. '?',
                        content = ('%d player(s) are on shift. Their shifts end and their deposits are refunded.'):format(j.working),
                        centered = true,
                        cancel = true,
                    })
                    if confirm ~= 'confirm' then return end
                end
                TriggerServerEvent('bdev-civilian-jobs:server:adminToggle', j.id)
            end,
        }
    end
    if #options == 0 then
        options[1] = { title = 'No job addons are running', description = 'Start an addon such as bdev-cj-roadside.', readOnly = true }
    end
    options[#options + 1] = {
        title = 'Reset all to config.lua',
        description = 'Forget the on/off choices made in game.',
        icon = 'rotate-left',
        onSelect = function() TriggerServerEvent('bdev-civilian-jobs:server:adminReset') end,
    }
    lib.registerContext({ id = 'civjobs_admin', title = 'Civilian Jobs: on / off', options = options })
    lib.showContext('civjobs_admin')
end)
