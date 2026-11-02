-- NUI callbacks for the Gigs phone app (html/app). The page calls
-- fetch('https://bdev-civilian-jobs/<name>') and each one forwards to the server.

local function proxy(name, ...)
    local ok, a, b = pcall(lib.callback.await, 'bdev-civilian-jobs:' .. name, false, ...)
    if not ok then return { ok = false, error = 'Server did not respond.' } end
    return a, b
end

local function result(ok, msg)
    if ok then return { ok = true, data = msg } end
    return { ok = false, error = msg or 'Something went wrong.' }
end

RegisterNUICallback('app:data', function(_, cb)
    local data = proxy('app:data')
    if type(data) ~= 'table' or data.ok == false then return cb({ ok = false, error = 'Server did not respond.' }) end
    data.ok = true
    data.currency = Config.Currency
    data.minigameEase = Config.Levels.minigameEase
    cb(data)
end)

RegisterNUICallback('app:waypoint', function(data, cb)
    if data and tonumber(data.x) and tonumber(data.y) then
        SetNewWaypoint(tonumber(data.x) + 0.0, tonumber(data.y) + 0.0)
    end
    cb({ ok = true })
end)

RegisterNUICallback('app:endShift', function(_, cb)
    cb(result(proxy('app:endShift')))
end)

RegisterNUICallback('app:request', function(data, cb)
    cb(result(CJ.sendRequest(data.job, data.type, data.note)))
end)

RegisterNUICallback('app:cancel', function(_, cb)
    cb(result(proxy('request:cancel')))
end)

RegisterNUICallback('app:accept', function(data, cb)
    cb(result(proxy('request:accept', data.id)))
end)

RegisterNUICallback('app:rate', function(data, cb)
    local ok = proxy('request:rate', data.id, data.stars)
    if ok then CJ.pendingRating = nil end
    cb(result(ok, ok and nil or 'Could not save the rating.'))
end)
