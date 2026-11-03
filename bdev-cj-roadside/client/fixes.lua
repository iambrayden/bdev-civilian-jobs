-- Applies a repair to a vehicle. The server sends this to whichever client owns the
-- vehicle (usually its driver), since only the owner can change a networked car.

local function control(veh)
    if NetworkHasControlOfEntity(veh) then return true end
    local deadline = GetGameTimer() + 1500
    repeat
        NetworkRequestControlOfEntity(veh)
        Wait(0)
    until NetworkHasControlOfEntity(veh) or GetGameTimer() > deadline
    return NetworkHasControlOfEntity(veh)
end

function RoadsideSetFuel(veh, level)
    level = level + 0.0
    SetVehicleFuelLevel(veh, level)
    Entity(veh).state:set('fuel', level, true) -- ox_fuel / qbx statebag fuel
end

local function upright(veh)
    local h = GetEntityHeading(veh)
    local c = GetEntityCoords(veh)
    SetEntityCoords(veh, c.x, c.y, c.z + 1.0, false, false, false, false)
    SetEntityRotation(veh, 0.0, 0.0, h, 2, true)
    SetVehicleOnGroundProperly(veh)
end

RegisterNetEvent('bdev-cj-roadside:client:applyFix', function(netId, fix)
    if type(fix) ~= 'table' or not NetworkDoesNetworkIdExist(netId) then return end
    local veh = NetToVeh(netId)
    if veh == 0 or not DoesEntityExist(veh) then return end
    control(veh)

    local k = fix.kind
    if k == 'tire' then
        SetVehicleTyreFixed(veh, fix.wheel)
    elseif k == 'engine' or k == 'coolant' then
        SetVehicleEngineHealth(veh, (fix.engine or 1000.0) + 0.0)
        SetVehicleUndriveable(veh, false)
    elseif k == 'battery' then
        if GetVehicleEngineHealth(veh) < 600.0 then SetVehicleEngineHealth(veh, 600.0) end
        SetVehicleUndriveable(veh, false)
        SetVehicleEngineOn(veh, true, true, false)
    elseif k == 'fuel' then
        if GetVehicleFuelLevel(veh) < (fix.fuel or 40.0) then RoadsideSetFuel(veh, fix.fuel or 40.0) end
        SetVehicleUndriveable(veh, false)
    elseif k == 'flipped' then
        upright(veh)
    elseif k == 'body' then
        SetVehicleBodyHealth(veh, 1000.0)
        SetVehicleDeformationFixed(veh)
        for i = 0, 7 do FixVehicleWindow(veh, i) end
    elseif k == 'full' or k == 'npc' then
        local fuel = GetVehicleFuelLevel(veh)
        if k == 'full' then
            SetVehicleFixed(veh)
            SetVehicleDeformationFixed(veh)
            SetVehicleBodyHealth(veh, 1000.0)
        end
        for _, w in ipairs({ 0, 1, 2, 3, 4, 5 }) do SetVehicleTyreFixed(veh, w) end
        SetVehicleEngineHealth(veh, (fix.engine or 1000.0) + 0.0)
        if fuel < (fix.fuel or 40.0) then RoadsideSetFuel(veh, fix.fuel or 40.0) end
        if IsEntityUpsidedown(veh) or math.abs(GetEntityRoll(veh)) > 60.0 then upright(veh) end
        SetVehicleUndriveable(veh, false)
    end
end)
