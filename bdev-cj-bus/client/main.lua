-- Driver side: routes, stops, doors, NPC passengers, fares and ride quality.

local JOB = Config.Job.id

local trip        -- { route, label, zone, stops, idx, due }
local stopBlip
local atStop = false
local boarding = false
local passengers = {} -- pid -> ped
local reservedSeats = {}

local function bus()
    return CivJobs.vehicle()
end

local function driving()
    local b = bus()
    return b and GetPedInVehicleSeat(b, -1) == cache.ped and b or nil
end

local function frontDoor(b)
    local _, max = GetModelDimensions(GetEntityModel(b))
    return GetOffsetFromEntityInWorldCoords(b, 1.4, max.y - 1.2, 0.0)
end

local function setDoors(b, open)
    for d = 0, 3 do
        if open then SetVehicleDoorOpen(b, d, false, false) else SetVehicleDoorShut(b, d, false) end
    end
end

local function penalty(kind, msg)
    TriggerServerEvent('bdev-cj-bus:server:penalty', kind)
    if msg then CivJobs.notify(msg, 'warning', 'Passengers') end
end

local function clearPassengers()
    for pid, p in pairs(passengers) do
        CivJobs.deleteEntity(p)
        passengers[pid] = nil
    end
    reservedSeats = {}
end

local function clearTrip()
    CivJobs.removeBlip(stopBlip)
    stopBlip = nil
    trip, atStop, boarding = nil, false, false
    lib.hideTextUI()
    clearPassengers()
end

local function fmtDue(sec)
    local neg = sec < 0
    sec = math.abs(math.floor(sec))
    return ('%s%d:%02d'):format(neg and '-' or '', sec // 60, sec % 60)
end

local function setStop()
    CivJobs.removeBlip(stopBlip)
    local stop = trip and trip.stops[trip.idx]
    if not stop then return end
    stopBlip = CivJobs.blip(stop.coords, ('Bus stop: %s'):format(stop.label), 513, 38, true)
end

--------------------------------------------------------------------------------
-- Route picker
--------------------------------------------------------------------------------
local function openRoutes()
    if trip then return CivJobs.notify('Finish your current route first.', 'error') end
    local list = lib.callback.await('bdev-cj-bus:routes', false) or {}
    local options = {}
    for _, r in ipairs(list) do
        options[#options + 1] = {
            title = r.label,
            description = r.locked and ('Unlocks at level %d'):format(r.minLevel) or ('%d stops · up to $%d route bonus'):format(r.stops, r.bonus),
            icon = 'bus',
            disabled = r.locked,
            onSelect = function()
                local ok, data = lib.callback.await('bdev-cj-bus:start', false, r.id)
                if not ok then return CivJobs.notify(data or 'Could not start that route.', 'error') end
                trip = data
                trip.dueBase = GetGameTimer()
                setStop()
                CivJobs.notify(('%s started. First stop: %s.'):format(trip.label, trip.stops[1].label), 'success', Config.Job.label)
            end,
        }
    end
    lib.registerContext({ id = 'bus_routes', title = 'Pick a route', options = options })
    lib.showContext('bus_routes')
end

RegisterCommand('busroute', function()
    if CivJobs.current(JOB) then openRoutes() end
end, false)

--------------------------------------------------------------------------------
-- Passengers
--------------------------------------------------------------------------------
local PED_MODELS = { 'a_m_y_business_01', 'a_f_y_business_01', 'a_m_m_eastsa_01', 'a_f_m_bevhills_01', 'a_m_y_hipster_01',
    'a_f_y_tourist_01', 'a_m_m_farmer_01', 'a_f_y_vinewood_01', 'a_m_y_stbla_01', 'a_f_m_downtown_01' }

local function freeSeat(b)
    local max = GetVehicleMaxNumberOfPassengers(b)
    for s = 1, max - 1 do
        if IsVehicleSeatFree(b, s) and not reservedSeats[s] then return s end
    end
end

local function alight(b, ids)
    for _, pid in ipairs(ids or {}) do
        local p = passengers[pid]
        passengers[pid] = nil
        if p and DoesEntityExist(p) then
            for s, owner in pairs(reservedSeats) do if owner == pid then reservedSeats[s] = nil end end
            TaskLeaveVehicle(p, b, 0)
            SetTimeout(2500, function()
                if DoesEntityExist(p) then TaskWanderStandard(p, 10.0, 10) end
                SetTimeout(9000, function() CivJobs.deleteEntity(p) end)
            end)
        end
    end
end

local function board(b, list, stop)
    for _, info in ipairs(list or {}) do
        if not atStop or not trip then return end
        local spot = vec3(stop.coords.x + math.random(-3, 3), stop.coords.y + math.random(-3, 3), stop.coords.z)
        local p = CivJobs.spawnPed(PED_MODELS[math.random(#PED_MODELS)], vec3(spot.x, spot.y, CivJobs.groundZ(spot)), 0.0)
        if p then
            local door = frontDoor(b)
            TaskGoStraightToCoord(p, door.x, door.y, door.z, 1.2, 8000, GetEntityHeading(b), 0.5)
            local res
            if info.kind == 'cash' then
                res = CivJobs.minigame('change', { title = 'Fare: make change', count = 1 })
            else
                res = CivJobs.minigame('pass', { title = 'Check the pass', zone = trip.zone })
            end
            if res.cancelled then res = { success = false, accepted = false } end
            local ok, out = lib.callback.await('bdev-cj-bus:fare', false, info.id, res)
            if ok and out and out.boarded then
                local seat = freeSeat(b)
                if seat then
                    reservedSeats[seat] = info.id
                    passengers[info.id] = p
                    TaskEnterVehicle(p, b, 10000, seat, 1.0, 1, 0)
                    SetTimeout(11000, function()
                        if DoesEntityExist(p) and not IsPedInVehicle(p, b, false) and IsVehicleSeatFree(b, seat) then
                            SetPedIntoVehicle(p, b, seat)
                        end
                    end)
                else
                    CivJobs.deleteEntity(p)
                end
                if info.kind == 'pass' and res.fake then CivJobs.notify('That pass was fake...', 'error', 'Passengers') end
            else
                if info.kind == 'pass' and res.success and not res.accepted then CivJobs.notify('Good catch, that pass was fake.', 'success') end
                if DoesEntityExist(p) then
                    ClearPedTasks(p)
                    TaskWanderStandard(p, 10.0, 10)
                    SetTimeout(8000, function() CivJobs.deleteEntity(p) end)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Stop handling
--------------------------------------------------------------------------------
local function arrive(b, stop)
    local dist = #(frontDoor(b) - stop.coords)
    local precision = math.max(0.0, 1.0 - dist / Config.StopRadius)
    local ok, res = lib.callback.await('bdev-cj-bus:arrive', false, trip.idx, precision)
    if not ok then
        if type(res) == 'string' then CivJobs.notify(res, 'error') end
        return
    end
    atStop = true
    boarding = true
    setDoors(b, true)
    local late = res.late or 0
    CivJobs.notify(('%s · %s%s'):format(stop.label,
        precision > 0.8 and 'right on the mark' or precision > 0.5 and 'decent stop' or 'a bit far from the stop',
        late > Config.LateGrace and (' · %ds late'):format(late) or ''), 'inform', Config.Job.label)
    CreateThread(function()
        alight(b, res.alight)
        Wait(800)
        board(b, res.board, stop)
        boarding = false
    end)
end

local function depart(b)
    setDoors(b, false)
    local ok, res = lib.callback.await('bdev-cj-bus:depart', false, trip.idx)
    if not ok then return end
    atStop = false
    if res.done then
        CivJobs.notify(('Route complete! %.1f stars, %d complaint(s).'):format(res.rating, res.complaints), 'success', Config.Job.label)
        local b2 = b
        SetTimeout(15000, function() alight(b2, (function() local ids = {} for pid in pairs(passengers) do ids[#ids + 1] = pid end return ids end)()) end)
        trip = nil
        CivJobs.removeBlip(stopBlip)
        stopBlip = nil
        lib.hideTextUI()
        SetTimeout(1500, openRoutes)
        return
    end
    if res.early then CivJobs.notify('You left ahead of the timetable. Riders missed the bus!', 'warning', 'Passengers') end
    trip.idx = trip.idx + 1
    setStop()
end

-- main loop: marker, stop prompts, HUD
CreateThread(function()
    local shown
    while true do
        local sleep = 500
        local b = trip and driving()
        if b then
            local stop = trip.stops[trip.idx]
            if stop then
                local pos = GetEntityCoords(b)
                local d = #(pos - stop.coords)
                local text
                if d < 90.0 then
                    sleep = 0
                    DrawMarker(1, stop.coords.x, stop.coords.y, stop.coords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        8.0, 8.0, 0.8, 245, 165, 36, 90, false, false, 2, false, nil, nil, false)
                    local still = GetEntitySpeed(b) < 0.6
                    if not atStop and still and #(frontDoor(b) - stop.coords) < Config.StopRadius then
                        text = '[E] Open the doors'
                        if IsControlJustPressed(0, 38) then arrive(b, stop) end
                    elseif atStop and boarding then
                        text = 'Passengers boarding…'
                    elseif atStop then
                        text = '[E] Close the doors and go'
                        if IsControlJustPressed(0, 38) then depart(b) end
                    end
                end
                if not text then
                    local due = (trip.due[trip.idx] or 0) - (GetGameTimer() - trip.dueBase) / 1000
                    text = ('Next: %s · %dm · due %s'):format(stop.label, math.floor(d), fmtDue(due))
                end
                if text ~= shown then
                    lib.showTextUI(text, { position = 'top-center' })
                    shown = text
                end
            end
        elseif shown then
            lib.hideTextUI()
            shown = nil
        end
        Wait(sleep)
    end
end)

-- ride quality
CreateThread(function()
    local last, cool = 0.0, {}
    local fastFor = 0
    while true do
        Wait(250)
        local b = trip and driving()
        if b then
            local now = GetGameTimer()
            local speed = GetEntitySpeed(b)
            local accel = (speed - last) / 0.25
            last = speed
            if accel < -7.0 and (cool.brake or 0) < now then
                cool.brake = now + 4000
                penalty('brake', 'Hard braking! Someone dropped their coffee.')
            end
            if HasEntityCollidedWithAnything(b) and speed > 3.0 and (cool.crash or 0) < now then
                cool.crash = now + 5000
                penalty('crash', 'Ouch! The passengers felt that.')
            end
            if speed > Config.SpeedLimit then fastFor = fastFor + 0.25 else fastFor = 0 end
            if fastFor > 3.0 and (cool.speed or 0) < now then
                cool.speed = now + 15000
                penalty('speed', 'Slow down! This is a bus, not a race car.')
            end
            if atStop and speed > 2.0 and (cool.doors or 0) < now then
                cool.doors = now + 15000
                penalty('doors', 'You pulled away with the doors open!')
            end
        else
            last = 0.0
        end
    end
end)

--------------------------------------------------------------------------------
-- Real players
--------------------------------------------------------------------------------
RegisterNetEvent('bdev-cj-bus:client:bell', function()
    PlaySoundFrontend(-1, 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET', true)
    CivJobs.notify('Stop requested!', 'inform', 'Bell')
end)

RegisterNetEvent('bdev-cj-bus:client:waiting', function(_, coords)
    local b = CivJobs.blip(coords, 'Waiting passenger', 280, 3, false)
    SetTimeout(180000, function() CivJobs.removeBlip(b) end)
end)

--------------------------------------------------------------------------------
-- Shift
--------------------------------------------------------------------------------
local BUS_OPTIONS = {
    {
        name = 'bus_route', icon = 'fa-solid fa-route', label = 'Pick a route', distance = 4.0,
        canInteract = function() return CivJobs.current(JOB) ~= nil and not trip end,
        onSelect = openRoutes,
    },
    {
        name = 'bus_abandon', icon = 'fa-solid fa-ban', label = 'Abandon this route', distance = 4.0,
        canInteract = function() return trip ~= nil and not atStop end,
        onSelect = function()
            if lib.alertDialog({ header = 'Abandon route?', content = 'You lose the route bonus.', centered = true, cancel = true }) ~= 'confirm' then return end
            if lib.callback.await('bdev-cj-bus:abandon', false) then clearTrip() end
        end,
    },
}
local busNet

CivJobs.onStart(JOB, function(session)
    busNet = session.netId
    if busNet then exports.ox_target:addEntity(busNet, BUS_OPTIONS) end
    Wait(800)
    openRoutes()
end)

CivJobs.onStop(JOB, function()
    clearTrip()
    if busNet then exports.ox_target:removeEntity(busNet, { 'bus_route', 'bus_abandon' }) end
    busNet = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearTrip() end
end)
