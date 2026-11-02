-- Rider side (every player): wait at a stop, pay when you get on, ring the bell.

local JOB = Config.Job.id
local paidFor = {} -- netId -> true
local riding

local function waitHere()
    if CivJobs.current(JOB) then return CivJobs.notify('You\'re driving the bus.', 'error') end
    local ok, res = lib.callback.await('bdev-cj-bus:wait', false)
    if not ok then return CivJobs.notify(res or 'Can\'t wait here.', 'error') end
    CivJobs.notify(res > 0 and ('The driver has been told. Fare: $%d.'):format(Config.Pay.playerFare)
        or 'No buses are running right now. Try again later.', res > 0 and 'success' or 'inform', 'LS Transit')
end

-- an ox_target spot at every stop on every route
CreateThread(function()
    local seen = {}
    for _, r in ipairs(Config.Routes) do
        for _, s in ipairs(r.stops) do
            local key = ('%d:%d'):format(math.floor(s.coords.x), math.floor(s.coords.y))
            if not seen[key] then
                seen[key] = true
                exports.ox_target:addSphereZone({
                    coords = s.coords, radius = 2.5, debug = Config.Debug,
                    options = { {
                        name = 'bus_wait', icon = 'fa-solid fa-bus', label = ('Wait for the bus (%s)'):format(s.label),
                        canInteract = function() return not CivJobs.current(JOB) and not IsPedInAnyVehicle(cache.ped, false) end,
                        onSelect = waitHere,
                    } },
                })
            end
        end
    end
end)

RegisterCommand(Config.WaitCommand, function()
    local pos = GetEntityCoords(cache.ped)
    for _, r in ipairs(Config.Routes) do
        for _, s in ipairs(r.stops) do
            if #(pos - s.coords) < 30.0 then return waitHere() end
        end
    end
    CivJobs.notify('Go to a bus stop first.', 'error')
end, false)

-- pay when you sit down in a running bus
CreateThread(function()
    while true do
        Wait(1000)
        local veh = cache.vehicle
        if veh and cache.seat ~= -1 and Entity(veh).state.civbus then
            local netId = VehToNet(veh)
            if not paidFor[netId] then
                paidFor[netId] = true
                local ok, res = lib.callback.await('bdev-cj-bus:boardPlayer', false, netId)
                if ok then
                    riding = netId
                    CivJobs.notify(('Fare paid: $%d. Press %s to ring the bell for your stop.'):format(res or Config.Pay.playerFare, Config.BellKey), 'success', 'LS Transit')
                else
                    paidFor[netId] = nil
                    if res then
                        CivJobs.notify(res, 'error', 'LS Transit')
                        TaskLeaveVehicle(cache.ped, veh, 0)
                        Wait(4000)
                    end
                end
            end
        elseif not veh then
            riding = nil
        end
    end
end)

lib.addKeybind({
    name = 'busbell',
    description = 'Ring the bus stop bell',
    defaultKey = Config.BellKey,
    onPressed = function()
        if riding and cache.vehicle and VehToNet(cache.vehicle) == riding then
            TriggerServerEvent('bdev-cj-bus:server:bell')
            CivJobs.notify('Stop requested.', 'inform', 'LS Transit')
        end
    end,
})
