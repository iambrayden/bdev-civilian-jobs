-- /civjobs: turn job addons on / off (in game menu or server console).

local function adminList()
    local counts = {}
    for _, s in pairs(CJ.Sessions) do counts[s.job] = (counts[s.job] or 0) + 1 end
    local list = {}
    for id, job in pairs(CJ.Jobs) do
        list[#list + 1] = {
            id = id,
            label = job.label,
            resource = job.resource,
            enabled = CJ.isEnabled(id),
            overridden = CJ.hasOverride(id),
            working = counts[id] or 0,
        }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

local function isAdmin(src)
    return src == 0 or IsPlayerAceAllowed(src, 'command.civjobs')
end

lib.addCommand('civjobs', {
    help = 'Manage civilian jobs (no arguments opens the menu)',
    params = {
        { name = 'action', type = 'string', help = 'list | enable | disable | reset | pos', optional = true },
        { name = 'job', type = 'string', help = 'job id, e.g. roadside', optional = true },
    },
    restricted = Config.AdminGroup,
}, function(source, args)
    local action = args.action and args.action:lower()
    local function reply(msg)
        if source == 0 then print('[civjobs] ' .. msg) else CJ.notify(source, msg, 'inform', 'Civilian Jobs') end
    end

    if not action then
        if source == 0 then
            action = 'list'
        else
            return TriggerClientEvent('bdev-civilian-jobs:client:admin', source, adminList())
        end
    end

    if action == 'list' then
        local list = adminList()
        if #list == 0 then return reply('No job addons are running.') end
        for _, j in ipairs(list) do
            reply(('%-4s %-14s %-24s %d on shift (%s)%s'):format(j.enabled and 'ON' or 'OFF', j.id, j.label,
                j.working, j.resource, j.overridden and ' [set in game]' or ''))
        end
    elseif action == 'enable' or action == 'disable' then
        if not args.job or not CJ.Jobs[args.job] then return reply('Unknown job id. Use "civjobs list".') end
        CJ.setEnabled(args.job, action == 'enable')
        reply(('%s is now %s.'):format(CJ.Jobs[args.job].label, action == 'enable' and 'ON' or 'OFF'))
    elseif action == 'reset' then
        if args.job then
            if not CJ.Jobs[args.job] then return reply('Unknown job id.') end
            CJ.setEnabled(args.job, nil)
            reply(('%s is back to its config.lua setting.'):format(CJ.Jobs[args.job].label))
        else
            CJ.resetOverrides()
            reply('All jobs are back to their config.lua settings.')
        end
    elseif action == 'pos' and source ~= 0 then
        CJ.copyPosition(source)
    else
        reply('Usage: civjobs [list | enable <job> | disable <job> | reset [job] | pos]')
    end
end)

RegisterNetEvent('bdev-civilian-jobs:server:adminToggle', function(id)
    local src = source
    if not isAdmin(src) or type(id) ~= 'string' or not CJ.Jobs[id] then return end
    CJ.setEnabled(id, not CJ.isEnabled(id))
    CJ.notify(src, ('%s is now %s.'):format(CJ.Jobs[id].label, CJ.isEnabled(id) and 'ON' or 'OFF'), 'success')
    TriggerClientEvent('bdev-civilian-jobs:client:admin', src, adminList())
end)

RegisterNetEvent('bdev-civilian-jobs:server:adminReset', function()
    local src = source
    if not isAdmin(src) then return end
    CJ.resetOverrides()
    CJ.notify(src, 'All jobs are back to their config.lua settings.', 'success')
    TriggerClientEvent('bdev-civilian-jobs:client:admin', src, adminList())
end)
