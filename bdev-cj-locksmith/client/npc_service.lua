-- Nobody was on duty: an NPC locksmith drives out to the requester (car or front door).

local active

RegisterNetEvent('bdev-cj-locksmith:client:npcService', function(reqId, kind, netId, coords)
    if active then active.visit.abort() end
    local target
    if netId then
        local v = NetworkDoesNetworkIdExist(netId) and NetToVeh(netId) or 0
        if v ~= 0 then target = v end
    end
    target = target or (coords and vec3(coords.x, coords.y, coords.z))
    if not target then
        lib.callback.await('bdev-cj-locksmith:npcFailed', false, reqId)
        return CivJobs.notify('The NPC locksmith couldn\'t find you. You have been refunded.', 'error', Config.Job.label)
    end
    local cfg = Config.NpcService
    local me = { reqId = reqId }
    active = me
    me.visit = CivJobs.npcVisit({
        target = target,
        vehicle = cfg.vehicle,
        ped = cfg.ped,
        label = 'NPC locksmith',
        sprite = 134,
        color = 46,
        spawnDistance = cfg.spawnDistance,
        driveTimeout = cfg.driveTimeout,
        workTime = cfg.workTime,
        anim = Config.Anims.door,
        standAt = type(target) == 'number' and function(_, ent)
            return GetOffsetFromEntityInWorldCoords(ent, -1.4, 0.6, 0.0) -- driver's door
        end or nil,
        onWorkStart = function()
            return lib.callback.await('bdev-cj-locksmith:npcWorking', false, reqId) == true
        end,
        onWorkEnd = function()
            return lib.callback.await('bdev-cj-locksmith:npcDone', false, reqId) == true
        end,
        onFinish = function(success, msg, aborted)
            if active == me then active = nil end
            if aborted then return end
            if success then
                CivJobs.notify(kind == 'house' and 'You\'re back in. Don\'t lose those keys again!' or 'All done. Here are your keys.', 'success', 'NPC locksmith')
            else
                lib.callback.await('bdev-cj-locksmith:npcFailed', false, reqId)
                CivJobs.notify((msg or 'The NPC locksmith couldn\'t finish.') .. ' You have been refunded.', 'error', Config.Job.label)
            end
        end,
    })
end)

RegisterNetEvent('bdev-cj-locksmith:client:npcCancel', function(reqId)
    if active and active.reqId == reqId then
        active.visit.abort()
        active = nil
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and active then active.visit.abort() end
end)
