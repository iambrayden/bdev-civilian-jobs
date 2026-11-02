-- Requester side: nobody was on duty, so an NPC mechanic drives out, works on
-- the car and leaves. Runs on the requester's own client (CivJobs.npcVisit).

local active -- { reqId, visit }

RegisterNetEvent('bdev-cj-roadside:client:npcService', function(reqId, netId)
    if active then active.visit.abort() end
    local car = NetworkDoesNetworkIdExist(netId) and NetToVeh(netId) or 0
    if car == 0 or not DoesEntityExist(car) then
        lib.callback.await('bdev-cj-roadside:npcFailed', false, reqId)
        return CivJobs.notify('The NPC mechanic couldn\'t find your car. You have been refunded.', 'error', Config.Job.label)
    end
    local cfg = Config.NpcService
    local me = { reqId = reqId }
    active = me
    me.visit = CivJobs.npcVisit({
        target = car,
        vehicle = cfg.truck,
        ped = cfg.ped,
        label = 'NPC mechanic',
        sprite = 446,
        color = 47,
        spawnDistance = cfg.spawnDistance,
        driveTimeout = cfg.driveTimeout,
        workTime = cfg.workTime,
        scenario = 'PROP_HUMAN_BUM_BIN',
        onWorkStart = function()
            if NetworkHasControlOfEntity(car) then SetVehicleDoorOpen(car, 4, false, false) end
            return lib.callback.await('bdev-cj-roadside:npcWorking', false, reqId) == true
        end,
        onWorkEnd = function()
            if DoesEntityExist(car) and NetworkHasControlOfEntity(car) then SetVehicleDoorShut(car, 4, false) end
            return lib.callback.await('bdev-cj-roadside:npcDone', false, reqId) == true
        end,
        onFinish = function(success, msg, aborted)
            if active == me then active = nil end
            if aborted then return end
            if success then
                CivJobs.notify('All fixed. Drive safe!', 'success', 'NPC mechanic')
            else
                lib.callback.await('bdev-cj-roadside:npcFailed', false, reqId)
                CivJobs.notify((msg or 'The NPC mechanic couldn\'t finish.') .. ' You have been refunded.', 'error', Config.Job.label)
            end
        end,
    })
end)

RegisterNetEvent('bdev-cj-roadside:client:npcCancel', function(reqId)
    if active and active.reqId == reqId then
        active.visit.abort()
        active = nil
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and active then active.visit.abort() end
end)
