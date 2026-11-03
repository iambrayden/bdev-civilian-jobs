-- Worker side: calls, the broken-down NPC scene, ox_target options on the car and the truck.

local JOB = Config.Job.id

local call      -- the current call (from the server)
local blip
local veh       -- the car we're fixing
local ped       -- NPC customer
local arrived = false
local spawning = false
local busy = false
local carNet    -- netId the car options are attached to
local truckNet  -- netId the truck options are attached to

local CAR_OPTIONS = {}
local TRUCK_OPTIONS = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function pending(kind, wheel)
    if not call then return nil end
    for _, i in ipairs(call.issues or {}) do
        if not i.done and i.kind == kind and (wheel == nil or i.wheel == wheel) then return i end
    end
end

local function nearFront(entity)
    local min, max = GetModelDimensions(GetEntityModel(entity))
    local front = GetOffsetFromEntityInWorldCoords(entity, 0.0, max.y + 0.4, 0.0)
    return #(GetEntityCoords(cache.ped) - front) < 2.2
end

local function ready()
    return call ~= nil and not busy and arrived and (call.kind == 'npc' or call.diagnosed)
end

local function removeCarTargets()
    if carNet then
        local names = {}
        for _, o in ipairs(CAR_OPTIONS) do names[#names + 1] = o.name end
        exports.ox_target:removeEntity(carNet, names)
    end
    carNet = nil
end

local function addCarTargets(netId)
    if carNet == netId then return end
    removeCarTargets()
    carNet = netId
    exports.ox_target:addEntity(netId, CAR_OPTIONS)
end

local function deleteScene()
    if call and call.kind == 'npc' then
        for _, e in ipairs({ ped, veh }) do
            if e and DoesEntityExist(e) then
                SetEntityAsMissionEntity(e, true, true)
                DeleteEntity(e)
            end
        end
    end
    ped, veh = nil, nil
end

local function clearCall(keepEntities)
    removeCarTargets()
    CivJobs.removeBlip(blip)
    blip = nil
    if not keepEntities then deleteScene() end
    call, veh, ped = nil, nil, nil
    arrived, spawning, busy = false, false, false
    Roadside.forgetSpares()
end

--------------------------------------------------------------------------------
-- Doing a repair
--------------------------------------------------------------------------------
local function runFix(issue)
    if busy or not veh then return end
    busy = true
    local ok, q = Roadside[issue.kind](veh, issue)
    busy = false
    if not ok then
        if type(q) == 'string' then CivJobs.notify(q, 'error') end
        return
    end
    local myCall = call
    local done, left = lib.callback.await('bdev-cj-roadside:fix', false, call.id, issue.key, q)
    if not done then
        if type(left) == 'string' then CivJobs.notify(left, 'error') end
        return
    end
    if myCall == call then issue.done = true end
    if type(left) == 'number' and left > 0 then
        CivJobs.notify(('%s done. %d problem(s) left.'):format(issue.label, left), 'success')
    end
end

local function diagnose()
    if busy or not veh then return end
    busy = true
    local ok, report = Roadside.diagnose(veh)
    busy = false
    if not ok then
        if type(report) == 'string' then CivJobs.notify(report, 'error') end
        return
    end
    local done, res = lib.callback.await('bdev-cj-roadside:diagnose', false, call.id, report)
    if not done then
        if type(res) == 'string' then CivJobs.notify(res, 'error') end
        return
    end
    local names = {}
    for _, i in ipairs(res) do names[#names + 1] = i.label end
    CivJobs.notify('Diagnosis: ' .. table.concat(names, ', '), 'inform')
end

local function issueOption(name, kind, label, icon, extra)
    local o = {
        name = name,
        icon = icon,
        label = label,
        distance = 2.5,
        canInteract = function(entity)
            if not ready() then return false end
            local i = pending(kind, extra and extra.wheel)
            if not i then return false end
            if extra and extra.front then return nearFront(entity) end
            return true
        end,
        onSelect = function()
            local i = pending(kind, extra and extra.wheel)
            if i then runFix(i) end
        end,
    }
    if extra and extra.bones then o.bones = extra.bones end
    return o
end

CAR_OPTIONS = {
    {
        name = 'rs_diagnose', icon = 'fa-solid fa-laptop-code', label = 'Run diagnostics', distance = 2.5,
        canInteract = function() return call and call.kind == 'player' and arrived and not call.diagnosed and not busy end,
        onSelect = diagnose,
    },
    issueOption('rs_tire_0', 'tire', 'Change flat tire', 'fa-solid fa-circle-dot', { wheel = 0, bones = { 'wheel_lf' } }),
    issueOption('rs_tire_1', 'tire', 'Change flat tire', 'fa-solid fa-circle-dot', { wheel = 1, bones = { 'wheel_rf' } }),
    issueOption('rs_tire_4', 'tire', 'Change flat tire', 'fa-solid fa-circle-dot', { wheel = 4, bones = { 'wheel_lr' } }),
    issueOption('rs_tire_5', 'tire', 'Change flat tire', 'fa-solid fa-circle-dot', { wheel = 5, bones = { 'wheel_rr' } }),
    issueOption('rs_battery', 'battery', 'Jump start the battery', 'fa-solid fa-car-battery', { front = true }),
    issueOption('rs_engine', 'engine', 'Repair the engine', 'fa-solid fa-gears', { front = true }),
    issueOption('rs_coolant', 'coolant', 'Top up the coolant', 'fa-solid fa-temperature-high', { front = true }),
    issueOption('rs_fuel', 'fuel', 'Refuel', 'fa-solid fa-gas-pump'),
    issueOption('rs_flipped', 'flipped', 'Winch it upright', 'fa-solid fa-rotate'),
    issueOption('rs_body', 'body', 'Fix the body damage', 'fa-solid fa-hammer'),
    issueOption('rs_inspect', 'inspect', 'Safety inspection', 'fa-solid fa-clipboard-check'),
}

local function takeOption(name, kind, label, icon, prop, carry)
    return {
        name = name, icon = icon, label = label, distance = 3.0,
        canInteract = function() return call ~= nil and pending(kind) ~= nil and not CivJobs.isCarrying() end,
        onSelect = function()
            if lib.progressBar({ duration = 1200, label = label .. '…', disable = { move = true, car = true } }) then
                CivJobs.carry(prop, carry)
            end
        end,
    }
end

TRUCK_OPTIONS = {
    takeOption('rs_take_wheel', 'tire', 'Take a spare wheel', 'fa-solid fa-circle-dot', Config.Props.wheel,
        { dict = 'anim@heists@box_carry@', anim = 'idle', bone = 60309, offset = vec3(0.0, 0.12, 0.25), rot = vec3(0.0, 90.0, 0.0) }),
    takeOption('rs_take_fuel', 'fuel', 'Take a jerry can', 'fa-solid fa-gas-pump', Config.Props.jerrycan,
        { bone = 57005, offset = vec3(0.30, 0.0, -0.05), rot = vec3(0.0, 270.0, 90.0) }),
    takeOption('rs_take_coolant', 'coolant', 'Take coolant', 'fa-solid fa-flask', Config.Props.coolant,
        { bone = 57005, offset = vec3(0.13, 0.0, -0.02), rot = vec3(0.0, 270.0, 90.0) }),
    {
        name = 'rs_put_back', icon = 'fa-solid fa-box', label = 'Put it back', distance = 3.0,
        canInteract = function() return CivJobs.isCarrying() end,
        onSelect = function() CivJobs.dropCarry() end,
    },
    {
        name = 'rs_skip', icon = 'fa-solid fa-forward', label = 'Skip this call', distance = 3.0,
        canInteract = function() return call ~= nil and call.kind == 'npc' and not busy end,
        onSelect = function()
            local ok, msg = lib.callback.await('bdev-cj-roadside:skip', false)
            if ok then CivJobs.notify('Call skipped. Dispatch will send another.', 'inform')
            elseif msg then CivJobs.notify(msg, 'error') end
        end,
    },
}

--------------------------------------------------------------------------------
-- NPC scene
--------------------------------------------------------------------------------
local function breakVehicle(v, issues)
    SetVehicleDirtLevel(v, 9.0)
    SetVehicleIndicatorLights(v, 0, true)
    SetVehicleIndicatorLights(v, 1, true)
    SetVehicleEngineOn(v, false, true, true)
    for _, i in ipairs(issues) do
        if i.kind == 'tire' then
            SetVehicleTyreBurst(v, i.wheel, true, 1000.0)
        elseif i.kind == 'battery' then
            SetVehicleUndriveable(v, true)
        elseif i.kind == 'fuel' then
            RoadsideSetFuel(v, 0.0)
            SetVehicleUndriveable(v, true)
        elseif i.kind == 'coolant' then
            SetVehicleEngineHealth(v, 280.0) -- smoking
            SetVehicleUndriveable(v, true)
        elseif i.kind == 'flipped' then
            local c, h = GetEntityCoords(v), GetEntityHeading(v)
            SetEntityCoords(v, c.x, c.y, c.z + 1.2, false, false, false, false)
            SetEntityRotation(v, 0.0, 180.0, h, 2, true)
        end
    end
end

local function spawnScene()
    spawning = true
    local myCall = call
    local s = myCall.spot
    local found, node, heading = GetClosestVehicleNodeWithHeading(s.x, s.y, s.z, 1, 3.0, 0)
    if not found then node, heading = vec3(s.x, s.y, s.z), 0.0 end
    local onSide, side = GetPointOnRoadSide(node.x, node.y, node.z, 1)
    local p = onSide and side or node

    local okModel, vHash = pcall(lib.requestModel, myCall.model, 10000)
    local okPed, pHash = pcall(lib.requestModel, myCall.ped, 10000)
    if not okModel or not okPed or call ~= myCall then spawning = false return end

    local v = CreateVehicle(vHash, p.x, p.y, p.z + 0.5, heading, true, false)
    local deadline = GetGameTimer() + 3000
    while not NetworkGetEntityIsNetworked(v) and GetGameTimer() < deadline do Wait(0) end
    SetEntityAsMissionEntity(v, true, true)
    SetVehicleOnGroundProperly(v)
    SetVehicleDoorsLocked(v, 2)
    SetModelAsNoLongerNeeded(vHash)

    local off = GetOffsetFromEntityInWorldCoords(v, -2.3, 0.8, 0.0)
    local npc = CreatePed(4, pHash, off.x, off.y, off.z, heading + 90.0, true, false)
    SetModelAsNoLongerNeeded(pHash)
    SetEntityAsMissionEntity(npc, true, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
    SetPedFleeAttributes(npc, 0, false)
    TaskStartScenarioInPlace(npc, 'WORLD_HUMAN_STAND_MOBILE', 0, true)

    breakVehicle(v, myCall.issues)

    local vNet, pNet = VehToNet(v), PedToNet(npc)
    local ok = lib.callback.await('bdev-cj-roadside:spawned', false, myCall.id, vNet, pNet)
    if not ok or call ~= myCall then
        DeleteEntity(npc)
        DeleteEntity(v)
        spawning = false
        return
    end
    myCall.netId = vNet
    veh, ped = v, npc
    addCarTargets(vNet)
    spawning = false
end

local function npcDriveOff(quality)
    local v, p = veh, ped
    if not v or not p or not DoesEntityExist(v) or not DoesEntityExist(p) then return end
    local lines = quality >= 0.8 and { 'You\'re a lifesaver, thank you!', 'Wow, that was fast. Thanks!' }
        or quality >= 0.5 and { 'Thanks, I appreciate it.', 'Good enough to get me home. Thanks.' }
        or { 'Uh... thanks, I guess.', 'Took you long enough.' }
    CivJobs.notify(lines[math.random(#lines)], 'inform', 'Customer')
    CreateThread(function()
        SetVehicleDoorsLocked(v, 1)
        SetVehicleIndicatorLights(v, 0, false)
        SetVehicleIndicatorLights(v, 1, false)
        SetVehicleUndriveable(v, false)
        ClearPedTasks(p)
        TaskEnterVehicle(p, v, 10000, -1, 1.5, 1, 0)
        local deadline = GetGameTimer() + 12000
        while DoesEntityExist(p) and not IsPedInVehicle(p, v, false) and GetGameTimer() < deadline do Wait(250) end
        if not DoesEntityExist(p) or not DoesEntityExist(v) then return end
        if not IsPedInVehicle(p, v, false) then SetPedIntoVehicle(p, v, -1) end
        SetVehicleEngineOn(v, true, true, false)
        TaskVehicleDriveWander(p, v, 17.0, 786603)
        SetPedKeepTask(p, true)
        Wait(45000)
        for _, e in ipairs({ p, v }) do
            if DoesEntityExist(e) then
                SetEntityAsMissionEntity(e, true, true)
                DeleteEntity(e)
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- Call lifecycle
--------------------------------------------------------------------------------
local function watch(myCall)
    CreateThread(function()
        while call == myCall do
            local pos = GetEntityCoords(cache.ped)
            if myCall.netId and (not veh or not DoesEntityExist(veh)) and NetworkDoesNetworkIdExist(myCall.netId) then
                local v = NetToVeh(myCall.netId)
                if v ~= 0 and DoesEntityExist(v) then
                    veh = v
                    addCarTargets(myCall.netId)
                end
            end

            if myCall.kind == 'npc' and not spawning then
                if not myCall.netId and #(pos - vec3(myCall.spot.x, myCall.spot.y, myCall.spot.z)) < 160.0 then
                    spawnScene()
                elseif myCall.netId and not NetworkDoesNetworkIdExist(myCall.netId)
                    and #(pos - vec3(myCall.spot.x, myCall.spot.y, myCall.spot.z)) < 120.0 then
                    -- the car is gone (destroyed / cleaned up): ask for a new call
                    if lib.callback.await('bdev-cj-roadside:lost', false, myCall.id) then
                        CivJobs.notify('The customer\'s car is gone. Dispatch will send another call.', 'error')
                    end
                end
            end

            local target = veh and DoesEntityExist(veh) and GetEntityCoords(veh) or myCall.spot
            if blip then SetBlipCoords(blip, target.x, target.y, target.z) end

            if not arrived and veh and DoesEntityExist(veh) and #(pos - GetEntityCoords(veh)) < 30.0 then
                arrived = lib.callback.await('bdev-cj-roadside:arrived', false, myCall.id) == true
                if arrived then
                    if myCall.kind == 'npc' then
                        if myCall.line then CivJobs.notify(myCall.line, 'inform', 'Customer') end
                        if ped and DoesEntityExist(ped) then
                            ClearPedTasks(ped)
                            TaskTurnPedToFaceEntity(ped, cache.ped, 2000)
                        end
                    else
                        CivJobs.notify(('You\'re at %s\'s car. Run diagnostics to see what\'s wrong.'):format(myCall.requesterName or 'the'), 'inform')
                    end
                end
            end
            Wait(1000)
        end
    end)
end

RegisterNetEvent('bdev-cj-roadside:client:call', function(data)
    if not CivJobs.current(JOB) then return end
    -- same call updated (diagnosis, progress): keep the scene, refresh the data
    if call and call.id == data.id then
        call.issues = data.issues
        call.diagnosed = data.diagnosed
        return
    end
    clearCall()
    call = data
    local label = data.kind == 'player' and ('Player call: %s'):format(data.requesterName or 'customer')
        or ('Call: %s'):format(data.label)
    blip = CivJobs.blip(data.spot, label, 446, data.kind == 'player' and 3 or 47, true)
    if data.kind == 'player' then
        CivJobs.notify(('Head to %s\'s car.%s'):format(data.requesterName or 'the caller',
            data.note and (' Note: "%s"'):format(data.note) or ''), 'inform', Config.Job.label)
    else
        CivJobs.notify(('New call: %s. GPS set.'):format(data.label), 'inform', Config.Job.label)
    end
    watch(call)
end)

RegisterNetEvent('bdev-cj-roadside:client:callDone', function(callId, quality)
    if not call or call.id ~= callId then return end
    if call.kind == 'npc' then npcDriveOff(quality or 0.5) end
    clearCall(true)
end)

RegisterNetEvent('bdev-cj-roadside:client:clearCall', function()
    clearCall()
end)

--------------------------------------------------------------------------------
-- Shift
--------------------------------------------------------------------------------
CivJobs.onStart(JOB, function(session)
    if session.netId then
        truckNet = session.netId
        exports.ox_target:addEntity(truckNet, TRUCK_OPTIONS)
    end
    CivJobs.notify('Stay near your truck. Dispatch will send calls, and player requests show up in Gigs.', 'inform', Config.Job.label)
end)

CivJobs.onStop(JOB, function()
    clearCall()
    CivJobs.dropCarry()
    if truckNet then
        local names = {}
        for _, o in ipairs(TRUCK_OPTIONS) do names[#names + 1] = o.name end
        exports.ox_target:removeEntity(truckNet, names)
        truckNet = nil
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearCall()
end)
