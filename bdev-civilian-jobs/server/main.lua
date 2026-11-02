CJ.Resource = GetCurrentResourceName()

function CJ.debug(...)
    if Config.Debug then print('[civjobs]', ...) end
end

function CJ.getPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end

function CJ.citizenid(src)
    local p = CJ.getPlayer(src)
    return p and p.PlayerData.citizenid
end

function CJ.charName(src)
    local p = CJ.getPlayer(src)
    if not p then return 'Unknown' end
    local ci = p.PlayerData.charinfo or {}
    local name = ('%s %s'):format(ci.firstname or '', ci.lastname or ''):gsub('^%s+', ''):gsub('%s+$', '')
    return name ~= '' and name or 'Unknown'
end

function CJ.notify(src, msg, typ, title)
    TriggerClientEvent('ox_lib:notify', src, {
        title = title or 'Civilian Jobs',
        description = msg,
        type = typ or 'inform',
        duration = 7000,
    })
end

--- Phone push notification (Quasar V3) with an ox_lib notification as fallback.
function CJ.phoneNotify(src, title, text, typ)
    local sent = false
    if Config.Phone.enabled and GetResourceState(Config.Phone.resource) == 'started' then
        local ok, res = pcall(function()
            return exports[Config.Phone.resource]:sendPhoneNotification(src, {
                appId = Config.Phone.app.id,
                title = title,
                text = text,
                closeTimeout = 7000,
            })
        end)
        sent = ok and res ~= false
    end
    if not sent then CJ.notify(src, text, typ, title) end
end

function CJ.playerCoords(src)
    return GetEntityCoords(GetPlayerPed(src))
end

function CJ.near(a, b, dist)
    return CJ.dist(a, b) <= dist
end

--------------------------------------------------------------------------------
-- Money
--------------------------------------------------------------------------------

--- Takes `amount` from the first account in Config.Payment.chargeAccounts that can cover it.
--- Returns the account name, or nil if the player can't afford it.
function CJ.charge(src, amount, reason)
    if amount <= 0 then return 'bank' end
    local player = CJ.getPlayer(src)
    if not player then return nil end
    for _, acc in ipairs(Config.Payment.chargeAccounts) do
        if (player.PlayerData.money[acc] or 0) >= amount and player.Functions.RemoveMoney(acc, amount, reason) then
            return acc
        end
    end
    return nil
end

--- Pays a player who may have gone offline (falls back to their citizenid).
function CJ.addMoney(src, cid, acc, amount, reason)
    if amount <= 0 then return true end
    local player = src and CJ.getPlayer(src)
    if player and player.PlayerData.citizenid == cid then
        return player.Functions.AddMoney(acc, amount, reason)
    end
    if not cid then return false end
    local ok, res = pcall(function() return exports.qbx_core:AddMoney(cid, acc, amount, reason) end)
    return ok and res ~= false
end

--------------------------------------------------------------------------------
-- Vehicles
--------------------------------------------------------------------------------
function CJ.spawnVehicle(model, coords, props, warpPed)
    local ok, netId, veh = pcall(qbx.spawnVehicle, {
        model = model,
        spawnSource = coords,
        warp = warpPed,
        props = props,
    })
    if not ok or not netId then
        print(('[civjobs] failed to spawn %s: %s'):format(model, tostring(netId)))
        return nil
    end
    return netId, veh
end

function CJ.entityFromNet(netId)
    if not netId then return nil end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent and ent ~= 0 and DoesEntityExist(ent) then return ent end
    return nil
end

function CJ.deleteNet(netId)
    local ent = CJ.entityFromNet(netId)
    if ent then DeleteEntity(ent) end
end

function CJ.spawnClear(coords, radius)
    local c = vec3(coords.x, coords.y, coords.z)
    for _, v in ipairs(GetAllVehicles()) do
        if #(GetEntityCoords(v) - c) < radius then return false end
    end
    return true
end

function CJ.plate(prefix)
    prefix = (prefix or 'CIV'):upper():gsub('[^%w]', ''):sub(1, 4)
    local out = prefix
    while #out < 8 do out = out .. tostring(math.random(0, 9)) end
    return out
end

--- The vehicle the player is in, or the closest one within `radius`.
function CJ.playerVehicle(src, radius)
    local ped = GetPlayerPed(src)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh and veh ~= 0 then return veh end
    local pos = GetEntityCoords(ped)
    local best, bestDist = nil, radius or 6.0
    for _, v in ipairs(GetAllVehicles()) do
        local d = #(GetEntityCoords(v) - pos)
        if d < bestDist then best, bestDist = v, d end
    end
    return best
end

--------------------------------------------------------------------------------
-- Admin helper: copy your position for config files
--------------------------------------------------------------------------------
function CJ.copyPosition(src)
    local ped = GetPlayerPed(src)
    local c = GetEntityCoords(ped)
    local s = ('vec4(%.2f, %.2f, %.2f, %.1f)'):format(c.x, c.y, c.z, GetEntityHeading(ped))
    print('[civjobs] ' .. s)
    TriggerClientEvent('bdev-civilian-jobs:client:copy', src, s)
end
