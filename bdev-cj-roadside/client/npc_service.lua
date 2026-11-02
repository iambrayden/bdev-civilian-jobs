-- Requester side: nobody was on duty, so an NPC mechanic drives out in a service
-- truck, works on the car and drives off. Runs on the requester's own client.

local active -- { reqId, truck, ped, blip, aborted }

local function cleanup(job, keepDriving)
    if not job then return end
    if job.blip and DoesBlipExist(job.blip) then RemoveBlip(job.blip) end
    lib.hideTextUI()
    if keepDriving and job.ped and job.truck and DoesEntityExist(job.ped) and DoesEntityExist(job.truck) then
        local p, t = job.ped, job.truck
        CreateThread(function()
            TaskVehicleDriveWander(p, t, 17.0, 786603)
            SetPedKeepTask(p, true)
            Wait(30000)
            for _, e in ipairs({ p, t }) do
                if DoesEntityExist(e) then
                    SetEntityAsMissionEntity(e, true, true)
                    DeleteEntity(e)
                end
            end
        end)
    else
        for _, e in ipairs({ job.ped, job.truck }) do
            if e and DoesEntityExist(e) then
                SetEntityAsMissionEntity(e, true, true)
                DeleteEntity(e)
            end
        end
    end
    if active == job then active = nil end
end

local function waitFor(job, cond, ms)
    local deadline = GetGameTimer() + ms
    while not job.aborted and not cond() and GetGameTimer() < deadline do Wait(250) end
    return not job.aborted and cond()
end

local function fail(job, msg)
    if job.aborted then return cleanup(job) end
    lib.callback.await('bdev-cj-roadside:npcFailed', false, job.reqId)
    if msg then CivJobs.notify(msg, 'error', Config.Job.label) end
    cleanup(job, true)
end

RegisterNetEvent('bdev-cj-roadside:client:npcService', function(reqId, netId)
    if active then cleanup(active) end
    local job = { reqId = reqId }
    active = job

    CreateThread(function()
        local car = NetworkDoesNetworkIdExist(netId) and NetToVeh(netId) or 0
        if car == 0 or not DoesEntityExist(car) then return fail(job, 'The NPC mechanic couldn\'t find your car.') end
        local cfg = Config.NpcService

        -- spawn the truck on a road some distance away
        local carPos = GetEntityCoords(car)
        local angle = math.random() * math.pi * 2
        local probe = carPos + vec3(math.cos(angle) * cfg.spawnDistance, math.sin(angle) * cfg.spawnDistance, 0.0)
        local found, node, heading = GetClosestVehicleNodeWithHeading(probe.x, probe.y, probe.z, 1, 3.0, 0)
        if not found then node, heading = probe, 0.0 end
        local okT, tHash = pcall(lib.requestModel, cfg.truck, 10000)
        local okP, pHash = pcall(lib.requestModel, cfg.ped, 10000)
        if not okT or not okP then return fail(job, 'The NPC mechanic is unavailable.') end
        if job.aborted then return cleanup(job) end

        local truck = CreateVehicle(tHash, node.x, node.y, node.z + 0.5, heading, true, false)
        SetEntityAsMissionEntity(truck, true, true)
        SetVehicleOnGroundProperly(truck)
        local driver = CreatePedInsideVehicle(truck, 4, pHash, -1, true, false)
        SetEntityAsMissionEntity(driver, true, true)
        SetBlockingOfNonTemporaryEvents(driver, true)
        SetModelAsNoLongerNeeded(tHash)
        SetModelAsNoLongerNeeded(pHash)
        job.truck, job.ped = truck, driver

        local b = AddBlipForEntity(truck)
        SetBlipSprite(b, 446)
        SetBlipColour(b, 47)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName('NPC mechanic')
        EndTextCommandSetBlipName(b)
        job.blip = b
        lib.showTextUI('NPC mechanic on the way')

        -- drive over (move it closer if it gets stuck)
        local function close() return #(GetEntityCoords(truck) - GetEntityCoords(car)) < 14.0 end
        TaskVehicleDriveToCoordLongrange(driver, truck, carPos.x, carPos.y, carPos.z, 16.0, 786603, 10.0)
        if not waitFor(job, close, cfg.driveTimeout * 1000) then
            if job.aborted then return cleanup(job) end
            local f2, n2, h2 = GetClosestVehicleNodeWithHeading(carPos.x, carPos.y, carPos.z, 1, 3.0, 0)
            if f2 then
                SetEntityCoords(truck, n2.x, n2.y, n2.z + 0.5, false, false, false, false)
                SetEntityHeading(truck, h2)
            end
        end
        if job.aborted or not DoesEntityExist(car) then return fail(job, 'The NPC mechanic couldn\'t reach your car.') end

        -- park, walk to the front of the car
        TaskVehicleTempAction(driver, truck, 27, 2000)
        Wait(1500)
        TaskLeaveVehicle(driver, truck, 0)
        waitFor(job, function() return not IsPedInAnyVehicle(driver, false) end, 6000)
        local _, max = GetModelDimensions(GetEntityModel(car))
        local front = GetOffsetFromEntityInWorldCoords(car, 0.0, max.y + 0.9, 0.0)
        TaskGoStraightToCoord(driver, front.x, front.y, front.z, 1.0, 15000, GetEntityHeading(car) + 180.0, 0.5)
        if not waitFor(job, function() return #(GetEntityCoords(driver) - front) < 1.5 end, 15000) then
            if job.aborted then return cleanup(job) end
            SetEntityCoords(driver, front.x, front.y, front.z - 1.0, false, false, false, false)
        end
        TaskTurnPedToFaceEntity(driver, car, 1000)
        Wait(1000)

        if not lib.callback.await('bdev-cj-roadside:npcWorking', false, job.reqId) then return fail(job) end
        if NetworkHasControlOfEntity(car) then SetVehicleDoorOpen(car, 4, false, false) end
        TaskStartScenarioInPlace(driver, 'PROP_HUMAN_BUM_BIN', 0, true)
        local endsAt = GetGameTimer() + cfg.workTime * 1000
        while GetGameTimer() < endsAt and not job.aborted do
            lib.showTextUI(('NPC mechanic working… %ds'):format(math.ceil((endsAt - GetGameTimer()) / 1000)))
            Wait(1000)
        end
        if job.aborted then return cleanup(job) end
        ClearPedTasks(driver)
        if NetworkHasControlOfEntity(car) then SetVehicleDoorShut(car, 4, false) end

        if not lib.callback.await('bdev-cj-roadside:npcDone', false, job.reqId) then
            return fail(job, 'The NPC mechanic couldn\'t finish. You have been refunded.')
        end
        lib.hideTextUI()
        CivJobs.notify('All fixed. Drive safe!', 'success', 'NPC mechanic')

        -- back to the truck and away
        TaskEnterVehicle(driver, truck, 10000, -1, 1.5, 1, 0)
        waitFor(job, function() return IsPedInVehicle(driver, truck, false) end, 12000)
        if DoesEntityExist(driver) and not IsPedInVehicle(driver, truck, false) then SetPedIntoVehicle(driver, truck, -1) end
        cleanup(job, true)
    end)
end)

RegisterNetEvent('bdev-cj-roadside:client:npcCancel', function(reqId)
    if active and active.reqId == reqId then
        active.aborted = true
        cleanup(active)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and active then cleanup(active) end
end)
