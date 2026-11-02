-- Menus for service requests, so everything works without the phone too.
--   /service   request a service, see its status, cancel it
--   /jobqueue  on-duty workers: see and accept open requests

local function statusText(r)
    if r.status == 'open' then return ('Waiting for a worker (%s)'):format(CJ.duration(r.age))
    elseif r.status == 'assigned' then
        return ('%s is on the way%s'):format(r.workerName or 'A worker', r.workerDistance and (', %dm away'):format(r.workerDistance) or '')
    elseif r.status == 'working' then return ('%s is working on it'):format(r.workerName or 'The worker')
    elseif r.status == 'npc' then return 'An NPC is handling it' end
    return r.status
end

function CJ.openServiceMenu()
    local mine = lib.callback.await('bdev-civilian-jobs:request:mine', false)
    if mine then
        lib.registerContext({
            id = 'civjobs_myrequest',
            title = mine.label,
            options = {
                { title = statusText(mine), description = ('Paid %s (held until the job is done)'):format(CJ.money(mine.price)), icon = 'clock', readOnly = true },
                {
                    title = 'Cancel request',
                    icon = 'xmark',
                    disabled = mine.status == 'working' or mine.status == 'npc',
                    onSelect = function()
                        local ok, msg = lib.callback.await('bdev-civilian-jobs:request:cancel', false)
                        if not ok and msg then CJ.notify(msg, 'error') end
                    end,
                },
            },
        })
        return lib.showContext('civjobs_myrequest')
    end

    local options = {}
    for id, job in pairs(CJ.jobs()) do
        if job.enabled and job.requests then
            local r = job.requests
            options[#options + 1] = {
                title = r.label,
                description = r.description,
                icon = job.icon or 'phone',
                metadata = {
                    { label = 'Price', value = CJ.money(r.price) },
                    r.npcPrice and { label = 'If nobody is on duty (NPC)', value = CJ.money(r.npcPrice) } or nil,
                },
                onSelect = function()
                    local input = lib.inputDialog(r.label, {
                        { type = 'input', label = 'Note for the worker (optional)', max = 120 },
                    })
                    if not input then return end
                    local ok, res = lib.callback.await('bdev-civilian-jobs:request:create', false, id, input[1])
                    if not ok and res then CJ.notify(res, 'error') end
                end,
            }
        end
    end
    if #options == 0 then return CJ.notify('No services are available right now.', 'error') end
    table.sort(options, function(a, b) return a.title < b.title end)
    lib.registerContext({ id = 'civjobs_services', title = 'Request a service', options = options })
    lib.showContext('civjobs_services')
end

function CJ.openQueue()
    if not CJ.Current then return CJ.notify('You are not on a shift.', 'error') end
    local list = lib.callback.await('bdev-civilian-jobs:request:queue', false) or {}
    local options = {}
    for _, r in ipairs(list) do
        options[#options + 1] = {
            title = (r.assignedToMe and '[Yours] ' or '') .. r.requesterName,
            description = (r.note and ('"%s"  '):format(r.note) or '') .. (r.plate and ('Plate %s'):format(r.plate) or ''),
            icon = r.assignedToMe and 'location-arrow' or 'user',
            metadata = {
                { label = 'Distance', value = r.distance and (r.distance .. 'm') or '?' },
                { label = 'Pays', value = CJ.money(r.price) },
                { label = 'Waiting', value = CJ.duration(r.age) },
            },
            onSelect = function()
                if r.assignedToMe then
                    if r.coords then SetNewWaypoint(r.coords.x, r.coords.y) end
                    return
                end
                local ok, msg = lib.callback.await('bdev-civilian-jobs:request:accept', false, r.id)
                if not ok and msg then CJ.notify(msg, 'error') end
            end,
        }
    end
    if #options == 0 then options[1] = { title = 'No open requests', description = 'New ones show up on your phone.', readOnly = true } end
    lib.registerContext({ id = 'civjobs_queue', title = 'Open requests', options = options })
    lib.showContext('civjobs_queue')
end

function CJ.openRating(info)
    local options = {}
    for stars = 5, 1, -1 do
        options[#options + 1] = {
            title = string.rep('★', stars) .. string.rep('☆', 5 - stars),
            onSelect = function()
                lib.callback.await('bdev-civilian-jobs:request:rate', false, info.id, stars)
                CJ.notify('Thanks for the rating!', 'success')
            end,
        }
    end
    lib.registerContext({ id = 'civjobs_rate', title = ('Rate %s'):format(info.workerName or 'your worker'), options = options })
    lib.showContext('civjobs_rate')
end

RegisterNetEvent('bdev-civilian-jobs:client:rate', function(info)
    CJ.pendingRating = info
    -- without the phone app, ask straight away
    if not CJ.phoneReady() then CJ.openRating(info) end
end)

RegisterCommand(Config.Requests.command, function() CJ.openServiceMenu() end, false)
RegisterCommand(Config.Requests.queueCommand, function() CJ.openQueue() end, false)
