local JOB = Config.Job.id

CivJobs.register(Config.Job)

local trips = {}       -- driver src -> trip
local waiting = {}     -- player src -> { coords, since }
local riders = {}      -- player src -> driver src (paid for this trip)
local pairBonus = {}   -- 'driverCid:riderCid' -> os.time()
local nextPassenger = 0

local function routeById(id)
    for _, r in ipairs(Config.Routes) do
        if r.id == id then return r end
    end
end

local function citizenid(src)
    local p = exports.qbx_core:GetPlayer(src)
    return p and p.PlayerData.citizenid
end

local function busOf(src)
    return CivJobs.vehicle(src)
end

local function setStatus(src)
    local t = trips[src]
    if not t then return CivJobs.status(src, 'Pick a route at the depot.') end
    local stop = t.route.stops[t.idx]
    CivJobs.status(src, stop and ('%s · next: %s (%d/%d)'):format(t.route.label, stop.label, t.idx, #t.route.stops)
        or ('%s · heading back'):format(t.route.label))
end

local function publicTrip(t)
    local now = os.time()
    local due = {}
    for i, at in ipairs(t.schedule) do due[i] = at - now end
    return { route = t.route.id, label = t.route.label, zone = t.route.zone, stops = t.route.stops, idx = t.idx, due = due }
end

--------------------------------------------------------------------------------
-- Routes
--------------------------------------------------------------------------------
lib.callback.register('bdev-cj-bus:routes', function(src)
    if not CivJobs.session(src, JOB) then return {} end
    local level = CivJobs.level(src, JOB)
    local list = {}
    for _, r in ipairs(Config.Routes) do
        list[#list + 1] = { id = r.id, label = r.label, stops = #r.stops, bonus = r.bonus, minLevel = r.minLevel, locked = level < (r.minLevel or 1) }
    end
    return list
end)

lib.callback.register('bdev-cj-bus:start', function(src, routeId)
    if not CivJobs.session(src, JOB) then return false end
    if trips[src] then return false, 'Finish your current route first.' end
    local route = routeById(routeId)
    if not route then return false end
    if CivJobs.level(src, JOB) < (route.minLevel or 1) then return false, ('You need level %d for that route.'):format(route.minLevel) end
    local bus = busOf(src)
    if not bus then return false, 'Your bus is gone. End your shift at the depot.' end

    local now = os.time()
    local schedule, t, prev = {}, now + 30, GetEntityCoords(bus)
    for i, stop in ipairs(route.stops) do
        t = t + math.floor(#(prev - stop.coords) / Config.AvgSpeed) + (i > 1 and Config.Dwell or 0)
        schedule[i] = t
        prev = stop.coords
    end
    trips[src] = {
        route = route, idx = 1, schedule = schedule, startedAt = now,
        lastArrive = now, lastPos = GetEntityCoords(bus),
        complaints = 0, penalties = 0, precision = {}, aboard = {}, pending = {},
    }
    Entity(bus).state:set('civbus', src, true)
    pcall(SetVehicleDoorsLocked, bus, 1)
    setStatus(src)
    return true, publicTrip(trips[src])
end)

-- the driver's client reports harsh driving (braking, crashes, speeding, doors open)
RegisterNetEvent('bdev-cj-bus:server:penalty', function(kind)
    local t = trips[source]
    if not t or type(kind) ~= 'string' then return end
    t.penalties = math.min(t.penalties + 1, 40)
end)

lib.callback.register('bdev-cj-bus:arrive', function(src, idx, precision)
    local t = trips[src]
    if not t or idx ~= t.idx or t.atStop then return false end
    local stop = t.route.stops[idx]
    local bus = busOf(src)
    if not bus then return false, 'Your bus is gone.' end
    local pos = GetEntityCoords(bus)
    if #(pos - stop.coords) > Config.StopRadius + 6.0 then return false, 'Pull in closer to the stop.' end
    local elapsed = os.time() - t.lastArrive
    if elapsed < #(t.lastPos - pos) / Config.MaxSpeed then return false, 'That was impossibly fast.' end

    t.atStop = idx
    t.arrivedAt = os.time()
    t.lastArrive, t.lastPos = os.time(), pos
    precision = math.max(0.0, math.min(1.0, tonumber(precision) or 0.5))
    t.precision[#t.precision + 1] = precision
    local late = os.time() - t.schedule[idx]
    if late > Config.LateGrace then t.complaints = t.complaints + 1 end

    -- who gets off here
    local alight = {}
    for pid, p in pairs(t.aboard) do
        if p.dest == idx then
            alight[#alight + 1] = pid
            t.aboard[pid] = nil
        end
    end
    -- who's waiting (the last stop is drop-off only)
    local count = 0
    for _ in pairs(t.aboard) do count = count + 1 end
    local board = {}
    if idx < #t.route.stops then
        local n = math.random(Config.Passengers.min, Config.Passengers.max)
        n = math.min(n, Config.Capacity - count)
        for _ = 1, n do
            nextPassenger = nextPassenger + 1
            local p = { id = nextPassenger, kind = math.random() < Config.Passengers.cashChance and 'cash' or 'pass' }
            t.pending[p.id] = p
            board[#board + 1] = p
        end
    end

    CivJobs.reward(src, JOB, { pay = Config.Pay.stop * (0.5 + 0.5 * precision), xp = Config.XP.stop, label = stop.label, task = true })

    -- real players waiting here
    for w, info in pairs(waiting) do
        if #(info.coords - stop.coords) < 30.0 and GetPlayerName(w) then
            CivJobs.notify(w, ('Your bus is here: %s.'):format(t.route.label), 'success', 'LS Transit')
            CivJobs.notify(src, 'A passenger is waiting at this stop. Give them a moment to board.', 'inform', Config.Job.label)
            waiting[w] = nil
        end
    end
    setStatus(src)
    return true, { board = board, alight = alight, late = late }
end)

lib.callback.register('bdev-cj-bus:fare', function(src, pid, result)
    local t = trips[src]
    if not t or not t.atStop or type(result) ~= 'table' then return false end
    local p = t.pending[pid]
    if not p then return false end
    t.pending[pid] = nil
    local boarded = false
    if p.kind == 'cash' then
        if result.success then
            CivJobs.reward(src, JOB, { pay = Config.Pay.fare, xp = Config.XP.passenger, label = 'Fare', task = false })
            boarded = true
        else
            t.complaints = t.complaints + 1
            boarded = true -- they get on anyway, grumbling
        end
    else
        local accepted = result.accepted == true
        if result.success and accepted then
            CivJobs.reward(src, JOB, { pay = Config.Pay.pass, xp = Config.XP.passenger, label = 'Pass checked', task = false })
            boarded = true
        elseif result.success and not accepted then
            CivJobs.reward(src, JOB, { pay = Config.Pay.caught, xp = Config.XP.passenger, label = 'Fake pass caught', task = false })
        elseif accepted then
            t.complaints = t.complaints + 1 -- let a fake through
            boarded = true
        else
            t.complaints = t.complaints + 1 -- turned away a paying rider
        end
    end
    if boarded then
        local last = #t.route.stops
        p.dest = math.random(math.min(t.idx + 1, last), last)
        t.aboard[pid] = p
    end
    return true, { boarded = boarded, dest = p.dest }
end)

lib.callback.register('bdev-cj-bus:depart', function(src, idx)
    local t = trips[src]
    if not t or t.atStop ~= idx then return false end
    local early = t.schedule[idx] - os.time()
    if early > Config.EarlyGrace and idx < #t.route.stops then t.complaints = t.complaints + 1 end
    t.atStop = nil
    t.pending = {}
    t.idx = idx + 1
    if t.idx > #t.route.stops then
        local sum = 0
        for _, q in ipairs(t.precision) do sum = sum + q end
        local precision = #t.precision > 0 and sum / #t.precision or 0.5
        local rating = math.max(1.0, math.min(5.0, 5.0 - t.complaints * 0.5 - t.penalties * 0.2 + (precision - 0.5)))
        local bonus = math.floor(t.route.bonus * rating / 5.0)
        CivJobs.reward(src, JOB, { pay = bonus, xp = Config.XP.route, label = ('%s complete (%.1f stars)'):format(t.route.label, rating) })
        trips[src] = nil
        for r, d in pairs(riders) do if d == src then riders[r] = nil end end
        setStatus(src)
        return true, { done = true, rating = rating, complaints = t.complaints, bonus = bonus }
    end
    setStatus(src)
    return true, { done = false, early = early > Config.EarlyGrace }
end)

lib.callback.register('bdev-cj-bus:abandon', function(src)
    if not trips[src] then return false end
    trips[src] = nil
    setStatus(src)
    return true
end)

--------------------------------------------------------------------------------
-- Real players riding
--------------------------------------------------------------------------------
lib.callback.register('bdev-cj-bus:wait', function(src)
    if CivJobs.session(src, JOB) then return false, 'You\'re the driver.' end
    waiting[src] = { coords = CivJobs.coords(src), since = os.time() }
    -- tell on-duty drivers
    local drivers = exports['bdev-civilian-jobs']:GetOnDuty(JOB)
    for _, d in ipairs(drivers) do
        CivJobs.notify(d, 'A passenger is waiting at a bus stop. They\'re marked on your map.', 'inform', Config.Job.label)
        TriggerClientEvent('bdev-cj-bus:client:waiting', d, src, waiting[src].coords)
    end
    return true, #drivers
end)

lib.callback.register('bdev-cj-bus:boardPlayer', function(src, netId)
    local bus = CivJobs.entity(netId)
    if not bus then return false end
    local driver = Entity(bus).state.civbus
    if not driver or driver == src or not trips[driver] then return false end
    if GetVehiclePedIsIn(GetPlayerPed(src), false) ~= bus then return false end
    if riders[src] == driver then return true end
    local p = exports.qbx_core:GetPlayer(src)
    if not p then return false end
    local fare = Config.Pay.playerFare
    local paid = p.Functions.RemoveMoney('bank', fare, 'bus-fare') or p.Functions.RemoveMoney('cash', fare, 'bus-fare')
    if not paid then return false, ('You need $%d for the fare.'):format(fare) end
    riders[src] = driver
    waiting[src] = nil
    CivJobs.reward(driver, JOB, { pay = fare, raw = true, task = false, label = 'Rider fare' })
    local dc, rc = citizenid(driver), citizenid(src)
    local key = (dc or '?') .. ':' .. (rc or '?')
    if not pairBonus[key] or os.time() - pairBonus[key] > 1200 then
        pairBonus[key] = os.time()
        SetTimeout(1100, function()
            CivJobs.reward(driver, JOB, { pay = Config.Pay.playerBonus, xp = 3, label = 'Rider bonus', task = false, playerWork = true })
        end)
    end
    CivJobs.notify(driver, 'A passenger boarded and paid their fare.', 'success', Config.Job.label)
    return true, fare
end)

RegisterNetEvent('bdev-cj-bus:server:bell', function()
    local src = source
    local driver = riders[src]
    if not driver or not trips[driver] then return end
    if not CivJobs.throttle(src, 'bell', 5000) then return end
    TriggerClientEvent('bdev-cj-bus:client:bell', driver)
end)

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------
CivJobs.onStart(JOB, function(src) setStatus(src) end)

CivJobs.onStop(JOB, function(src)
    trips[src] = nil
    for r, d in pairs(riders) do if d == src then riders[r] = nil end end
end)

AddEventHandler('playerDropped', function()
    local src = source
    trips[src], waiting[src], riders[src] = nil, nil, nil
end)
