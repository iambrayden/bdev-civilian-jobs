local JOB = Config.Job.id

local call, blip, veh, ped, safeProp, zone, point
local busy = false
local carNet, truckNet
local refreshLabels -- defined below, used by runStep

--------------------------------------------------------------------------------
-- Request hooks: which house the requester is standing at (qs-housing)
--------------------------------------------------------------------------------
exports('RequestContext', function(typeId)
    if typeId ~= 'house' then return true, nil end
    if GetResourceState(Config.Housing.resource) ~= 'started' then return false, 'House lockouts aren\'t available here.' end
    local ok, house = pcall(Config.Housing.currentHouse)
    if not ok or house == nil then return false, 'Stand at the front door of your house.' end
    return true, { house = house }
end)

RegisterNetEvent('bdev-cj-locksmith:client:unlock', function(netId)
    if not NetworkDoesNetworkIdExist(netId) then return end
    local v = NetToVeh(netId)
    if v == 0 then return end
    NetworkRequestControlOfEntity(v)
    SetVehicleDoorsLocked(v, 1)
    SetVehicleDoorsLockedForAllPlayers(v, false)
end)

RegisterNetEvent('bdev-cj-locksmith:client:enterHouse', function(house)
    local ok, err = pcall(Config.Housing.enterHouse, house)
    if not ok then print('[locksmith] enterHouse failed: ' .. tostring(err)) end
end)

--------------------------------------------------------------------------------
-- Steps (minigames)
--------------------------------------------------------------------------------
local MG = CivJobs.minigame

local function face(coords)
    TaskTurnPedToFaceCoord(cache.ped, coords.x, coords.y, coords.z, 700)
    Wait(700)
end

local function withAnim(a, fn)
    CivJobs.playAnim(a.dict, a.clip, -1, 1)
    local res = fn()
    ClearPedTasks(cache.ped)
    return res
end

local STEP = {
    unlock = function(c)
        return withAnim(Config.Anims.door, function()
            if c.highSecurity then
                return MG('pins', { title = 'High-security lock: pick it', count = 6 })
            end
            return MG('slimjim', { title = 'Slim jim the door' })
        end)
    end,
    pick = function(c)
        return withAnim(Config.Anims.door, function()
            return MG('pins', { title = c.type == 'rekey' and 'Pick the old lock out' or 'Pick the lock', count = c.type == 'rekey' and 6 or 5 })
        end)
    end,
    cut = function(c)
        return withAnim(Config.Anims.bench, function()
            return MG('keycut', { title = c.type == 'rekey' and 'Cut the new key' or 'Cut the key', cuts = 5 })
        end)
    end,
    dial = function()
        return withAnim(Config.Anims.door, function()
            return MG('dial', { title = 'Crack the safe', numbers = 3 })
        end)
    end,
}

local function nextStep()
    if not call then return nil end
    for _, s in ipairs(call.steps) do
        if not s.done then return s end
    end
end

local function runStep(target)
    local s = nextStep()
    if busy or not s then return end
    busy = true
    if target then face(target) end
    local res = STEP[s.key](call)
    busy = false
    if not res or not res.success then
        if res and not res.cancelled then CivJobs.notify('Not quite. Try again.', 'error') end
        return
    end
    local myCall = call
    local ok, left = lib.callback.await('bdev-cj-locksmith:step', false, call.id, s.key, res.quality)
    if not ok then
        if type(left) == 'string' then CivJobs.notify(left, 'error') end
        return
    end
    if myCall == call then s.done = true end
    if type(left) == 'number' and left > 0 then
        refreshLabels()
        CivJobs.notify(('%s done. Next: %s.'):format(s.label, nextStep() and nextStep().label or ''), 'success')
    end
end

local function stepOption(name, icon)
    return {
        name = name, icon = icon, distance = 2.5,
        label = 'Work on it',
        canInteract = function() return call ~= nil and not busy and nextStep() ~= nil end,
        onSelect = function(data)
            local target = data and data.coords or (call and call.spot)
            runStep(target)
        end,
    }
end

-- label follows the next step
local CAR_OPTION = stepOption('ls_car', 'fa-solid fa-key')
local ZONE_OPTION = stepOption('ls_zone', 'fa-solid fa-key')
refreshLabels = function()
    local s = nextStep()
    local label = s and s.label or 'Work on it'
    CAR_OPTION.label = label
    ZONE_OPTION.label = label
end

--------------------------------------------------------------------------------
-- Scene
--------------------------------------------------------------------------------
local function removeTargets()
    if carNet then exports.ox_target:removeEntity(carNet, { 'ls_car' }) end
    carNet = nil
    if zone then exports.ox_target:removeZone(zone) end
    zone = nil
end

local function clearCall(keep)
    removeTargets()
    CivJobs.removeBlip(blip)
    blip = nil
    if point then point:remove() end
    point = nil
    if safeProp and DoesEntityExist(safeProp) then DeleteEntity(safeProp) end
    safeProp = nil
    if not keep and call and call.kind == 'npc' then
        CivJobs.deleteEntity(ped)
        CivJobs.deleteEntity(veh)
    end
    call, veh, ped, busy = nil, nil, nil, false
end

local function addCarTarget(netId)
    if carNet == netId then return end
    if carNet then exports.ox_target:removeEntity(carNet, { 'ls_car' }) end
    carNet = netId
    refreshLabels()
    exports.ox_target:addEntity(netId, { CAR_OPTION })
end

local function addZone(coords)
    if zone then return end
    refreshLabels()
    local z = CivJobs.groundZ(coords) + 1.0
    zone = exports.ox_target:addSphereZone({
        coords = vec3(coords.x, coords.y, z), radius = 1.3, debug = Config.Debug,
        options = { ZONE_OPTION },
    })
end

local function standIn(door, dist)
    local h = math.rad(door.w or 0.0)
    return vec3(door.x + math.sin(h) * dist, door.y - math.cos(h) * dist, door.z)
end

local function spawnScene(c)
    if c.type == 'car' and c.kind == 'npc' then
        local v, heading = CivJobs.spawnRoadsideVehicle(c.model, vec4(c.spot.x, c.spot.y, c.spot.z, 0.0), { locked = true })
        if not v or call ~= c then return CivJobs.deleteEntity(v) end
        local off = GetOffsetFromEntityInWorldCoords(v, -2.2, 0.6, 0.0)
        local p = CivJobs.spawnPed(c.ped, off, (heading or 0.0) + 90.0, 'WORLD_HUMAN_STAND_IMPATIENT')
        local ok = lib.callback.await('bdev-cj-locksmith:spawned', false, c.id, VehToNet(v), p and PedToNet(p) or nil)
        if not ok or call ~= c then
            CivJobs.deleteEntity(p)
            CivJobs.deleteEntity(v)
            return
        end
        c.netId = VehToNet(v)
        veh, ped = v, p
        addCarTarget(c.netId)
    else
        if c.type == 'safe' then
            local okm, hash = pcall(lib.requestModel, Config.Props.safe, 5000)
            if okm then
                local b = Config.Shop.bench
                safeProp = CreateObject(hash, b.x, b.y, b.z, false, false, false)
                SetEntityHeading(safeProp, b.w)
                PlaceObjectOnGroundProperly(safeProp)
                FreezeEntityPosition(safeProp, true)
                SetModelAsNoLongerNeeded(hash)
            end
        elseif c.ped then
            local at = c.door and standIn(c.door, 1.4) or vec3(Config.Shop.counter.x, Config.Shop.counter.y, Config.Shop.counter.z)
            local heading = c.door and c.door.w or Config.Shop.counter.w
            local p = CivJobs.spawnPed(c.ped, vec3(at.x, at.y, CivJobs.groundZ(at)), heading, 'WORLD_HUMAN_STAND_IMPATIENT')
            if p then
                lib.callback.await('bdev-cj-locksmith:spawned', false, c.id, nil, PedToNet(p))
                ped = p
            end
        end
        addZone(c.spot)
    end
end

local function customerReaction(c, quality)
    local lines = quality >= 0.8 and { 'Wow, that was quick. Thank you!', 'You\'re a lifesaver.' }
        or quality >= 0.5 and { 'Thanks, appreciate it.' }
        or { 'Finally. Thanks, I guess.' }
    if c.kind == 'npc' and c.type ~= 'safe' then CivJobs.notify(lines[math.random(#lines)], 'inform', 'Customer') end
    local p, v = ped, veh
    if c.type == 'car' and p and v then
        SetVehicleDoorsLocked(v, 1)
        CivJobs.driveAway(p, v, 40000)
    elseif p and DoesEntityExist(p) then
        CreateThread(function()
            ClearPedTasks(p)
            local to = c.door and vec3(c.door.x, c.door.y, c.door.z) or GetOffsetFromEntityInWorldCoords(p, 0.0, -10.0, 0.0)
            TaskGoStraightToCoord(p, to.x, to.y, to.z, 1.0, 8000, 0.0, 0.3)
            Wait(c.door and 4000 or 8000)
            CivJobs.deleteEntity(p)
        end)
    end
end

--------------------------------------------------------------------------------
-- Call lifecycle
--------------------------------------------------------------------------------
RegisterNetEvent('bdev-cj-locksmith:client:call', function(data)
    if not CivJobs.current(JOB) then return end
    clearCall()
    call = data
    local label = data.kind == 'player' and ('%s: %s'):format(data.requesterName or 'Caller', data.label) or ('Call: %s'):format(data.label)
    blip = CivJobs.blip(data.spot, label, 134, data.kind == 'player' and 3 or 46, true)
    CivJobs.notify(data.kind == 'player'
        and ('%s needs a locksmith (%s).%s'):format(data.requesterName or 'Someone', data.label, data.note and (' Note: "%s"'):format(data.note) or '')
        or ('New call: %s. GPS set.'):format(data.label), 'inform', Config.Job.label)

    if data.kind == 'player' then
        if data.netId then
            CreateThread(function()
                local myCall = call
                while call == myCall and not carNet do
                    if NetworkDoesNetworkIdExist(data.netId) then
                        local v = NetToVeh(data.netId)
                        if v ~= 0 then
                            veh = v
                            addCarTarget(data.netId)
                        end
                    end
                    Wait(1000)
                end
            end)
        else
            point = lib.points.new({ coords = vec3(data.spot.x, data.spot.y, data.spot.z), distance = 80.0, onEnter = function() addZone(data.spot) end })
        end
        return
    end

    local myCall = call
    point = lib.points.new({
        coords = vec3(data.spot.x, data.spot.y, data.spot.z),
        distance = 130.0,
        onEnter = function()
            if call ~= myCall or myCall.spawned then return end
            myCall.spawned = true
            spawnScene(myCall)
            if myCall.line and myCall.type ~= 'safe' then
                SetTimeout(4000, function() if call == myCall then CivJobs.notify(myCall.line, 'inform', 'Customer') end end)
            end
        end,
    })
end)

RegisterNetEvent('bdev-cj-locksmith:client:callDone', function(callId, quality)
    if not call or call.id ~= callId then return end
    customerReaction(call, quality or 0.5)
    clearCall(true)
end)

RegisterNetEvent('bdev-cj-locksmith:client:clearCall', function() clearCall() end)

--------------------------------------------------------------------------------
-- Shift
--------------------------------------------------------------------------------
local VAN_OPTIONS = {
    {
        name = 'ls_skip', icon = 'fa-solid fa-forward', label = 'Skip this call', distance = 3.0,
        canInteract = function() return call ~= nil and call.kind == 'npc' and not busy end,
        onSelect = function()
            local ok, msg = lib.callback.await('bdev-cj-locksmith:skip', false)
            if ok then CivJobs.notify('Call skipped. Dispatch will send another.', 'inform')
            elseif msg then CivJobs.notify(msg, 'error') end
        end,
    },
}

CivJobs.onStart(JOB, function(session)
    if session.netId then
        truckNet = session.netId
        exports.ox_target:addEntity(truckNet, VAN_OPTIONS)
    end
    CivJobs.notify('Calls come in by dispatch. Player requests show up in Gigs.', 'inform', Config.Job.label)
end)

CivJobs.onStop(JOB, function()
    clearCall()
    if truckNet then exports.ox_target:removeEntity(truckNet, { 'ls_skip' }) end
    truckNet = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearCall() end
end)
