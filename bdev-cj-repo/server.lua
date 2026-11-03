local JOB = Config.Job.id

CivJobs.register(Config.Job)

local cases = {} -- src -> case
local skips = {}
local nextCaseId = 0

local function plate()
    local chars = 'ABCDEFGHJKLMNPRSTUVWXYZ'
    local out = ''
    for i = 1, 8 do
        if i <= 3 then
            local n = math.random(#chars)
            out = out .. chars:sub(n, n)
        else
            out = out .. tostring(math.random(0, 9))
        end
    end
    return out
end

local function trim(s)
    local out = tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')
    return out
end

local function publicCase(c)
    return {
        id = c.id, model = c.model, plate = c.plate, owner = c.owner, color = c.color, owed = c.owed,
        search = c.search, radius = c.radius, spot = c.spot, witnesses = c.witnesses, asked = c.asked,
        netId = c.netId, found = c.found, unlocked = c.unlocked, hotwired = c.hotwired, strapped = c.strapped,
    }
end

local function setStatus(src)
    local c = cases[src]
    if not c then return CivJobs.status(src, 'Waiting for the next case…') end
    CivJobs.status(src, ('Case: %s %s, plate %s%s'):format(c.color, c.model, c.plate, c.found and ' (found)' or ''))
end

local function deleteCar(c)
    local e = c and CivJobs.entity(c.netId)
    if e then DeleteEntity(e) end
end

local function clearCase(src, tell, keepCar)
    local c = cases[src]
    if not c then return end
    cases[src] = nil
    if not keepCar then deleteCar(c) end
    if tell then TriggerClientEvent('bdev-cj-repo:client:clearCase', src) end
end

local function newCase(src)
    if cases[src] or not CivJobs.session(src, JOB) then return end
    local pos = CivJobs.coords(src)
    local options = {}
    for _, a in ipairs(Config.Areas) do
        if #(pos - a) > 300.0 then options[#options + 1] = a end
    end
    if #options == 0 then options = Config.Areas end
    local area = options[math.random(#options)]
    -- the car is somewhere in the area; the first search circle is centred off it
    local ang, r = math.random() * math.pi * 2, math.random() * 120.0
    local spot = vec3(area.x + math.cos(ang) * r, area.y + math.sin(ang) * r, area.z)
    local ang2, r2 = math.random() * math.pi * 2, math.random() * Config.AreaRadius * 0.5
    nextCaseId = nextCaseId + 1
    local color = Config.Colors[math.random(#Config.Colors)]
    local c = {
        id = nextCaseId,
        model = Config.Models[math.random(#Config.Models)],
        plate = plate(),
        owner = Config.Owners[math.random(#Config.Owners)],
        color = color,
        owed = math.random(18, 90) * 100,
        spot = spot,
        search = vec3(spot.x + math.cos(ang2) * r2, spot.y + math.sin(ang2) * r2, spot.z),
        radius = Config.AreaRadius,
        witnesses = Config.Witnesses,
        asked = {},
        createdAt = os.time(),
        quality = {},
    }
    cases[src] = c
    setStatus(src)
    TriggerClientEvent('bdev-cj-repo:client:case', src, publicCase(c))
end

local function scheduleCase(src, delay)
    local d = delay or math.random(Config.NextCaseDelay[1], Config.NextCaseDelay[2])
    SetTimeout(d * 1000, function()
        if CivJobs.session(src, JOB) and not cases[src] then newCase(src) end
    end)
end

local function workerCase(src, caseId)
    local c = cases[src]
    if not c or c.id ~= caseId or not CivJobs.session(src, JOB) then return nil end
    return c
end

local function carNear(src, c, dist)
    local car = CivJobs.entity(c.netId)
    return car and CivJobs.near(src, GetEntityCoords(car), dist) and car or nil
end

--------------------------------------------------------------------------------
-- Shift
--------------------------------------------------------------------------------
CivJobs.onStart(JOB, function(src)
    setStatus(src)
    scheduleCase(src, 5)
end)

CivJobs.onStop(JOB, function(src)
    clearCase(src, true)
end)

--------------------------------------------------------------------------------
-- Searching
--------------------------------------------------------------------------------
lib.callback.register('bdev-cj-repo:spawned', function(src, caseId, netId)
    local c = workerCase(src, caseId)
    if not c or (c.netId and CivJobs.entity(c.netId)) then return false end
    local car = CivJobs.entity(netId)
    if not car or GetEntityModel(car) ~= joaat(c.model) then return false end
    if trim(GetVehicleNumberPlateText(car)) ~= c.plate then return false end
    if #(GetEntityCoords(car) - c.spot) > 200.0 then return false end
    c.netId = netId
    pcall(SetEntityOrphanMode, car, 2)
    return true
end)

-- a witness: a real tip (the circle shrinks around the car) or a wrong one
lib.callback.register('bdev-cj-repo:ask', function(src, caseId, idx)
    local c = workerCase(src, caseId)
    idx = tonumber(idx)
    if not c or not idx or idx < 1 or idx > c.witnesses or c.asked[idx] then return false end
    if not CivJobs.near(src, c.search, c.radius + 60.0) then return false end
    if not CivJobs.throttle(src, 'ask', 4000) then return false end
    c.asked[idx] = true
    local truth = math.random() < math.min(0.95, Config.TruthChance + 0.03 * (CivJobs.level(src, JOB) - 1))
    local center
    if truth then
        local a, r = math.random() * math.pi * 2, math.random() * Config.ClueRadius * 0.6
        center = vec3(c.spot.x + math.cos(a) * r, c.spot.y + math.sin(a) * r, c.spot.z)
        c.search, c.radius = center, Config.ClueRadius
    else
        local a = math.random() * math.pi * 2
        center = vec3(c.spot.x + math.cos(a) * 180.0, c.spot.y + math.sin(a) * 180.0, c.spot.z)
    end
    -- the client only gets the tip, not whether it's true
    return true, { center = center, radius = Config.ClueRadius }
end)

-- the plate reader matched the car
lib.callback.register('bdev-cj-repo:found', function(src, caseId)
    local c = workerCase(src, caseId)
    if not c or c.found or not carNear(src, c, Config.ScanRange + 15.0) then return false end
    c.found = true
    CivJobs.reward(src, JOB, { pay = Config.Pay.found, xp = Config.XP.found, label = 'Plate match', task = false })
    setStatus(src)
    return true
end)

--------------------------------------------------------------------------------
-- Recovering
--------------------------------------------------------------------------------
-- step: 'unlock' | 'hotwire' | 'strap'. Returns ok, { confront = bool }
lib.callback.register('bdev-cj-repo:step', function(src, caseId, step, quality)
    local c = workerCase(src, caseId)
    if not c then return false end
    local car = carNear(src, c, 6.0)
    if not car then return false, 'Get closer to the car.' end
    if c.settled then return false end
    if step == 'unlock' then
        c.unlocked = true
    elseif step == 'hotwire' then
        if not c.unlocked then return false, 'Get the door open first.' end
        c.hotwired = true
        if GetResourceState('qbx_vehiclekeys') == 'started' then
            pcall(function() exports.qbx_vehiclekeys:GiveKeys(src, car, true) end)
        end
    elseif step == 'strap' then
        local truck = CivJobs.vehicle(src)
        if not truck or #(GetEntityCoords(truck) - GetEntityCoords(car)) > 14.0 then return false, 'Back the flatbed up to the car.' end
        c.strapped = true
    else
        return false
    end
    c.quality[#c.quality + 1] = math.max(0.0, math.min(1.0, tonumber(quality) or 0.5))
    c.found = true
    local confront = false
    if not c.confrontRolled then
        c.confrontRolled = true
        confront = math.random() < Config.Confront.chance
        c.confronting = confront
    end
    setStatus(src)
    return true, { confront = confront, owed = c.owed }
end)

-- the owner showed up. choice: 'order' | 'settle' | 'ignore'. outcome: 'leave' | 'attack' | 'settled'
lib.callback.register('bdev-cj-repo:confront', function(src, caseId, choice)
    local c = workerCase(src, caseId)
    if not c or not c.confronting then return false end
    c.confronting = false
    if choice == 'settle' then
        c.settled = true
        CivJobs.reward(src, JOB, { pay = Config.Pay.settle, xp = Config.XP.settled, label = 'Owner paid up' })
        clearCase(src, false, true) -- the owner keeps the car
        SetTimeout(500, function() setStatus(src) end)
        scheduleCase(src)
        return true, 'settled'
    end
    local calm = choice == 'order'
        and math.random() < math.min(0.95, Config.Confront.talkChance + 0.04 * (CivJobs.level(src, JOB) - 1))
    if calm then return true, 'leave' end
    return true, math.random() < Config.Confront.attackChance and 'attack' or 'leave'
end)

lib.callback.register('bdev-cj-repo:deliver', function(src, caseId)
    local c = workerCase(src, caseId)
    if not c or not (c.hotwired or c.strapped) then return false end
    local car = CivJobs.entity(c.netId)
    if not car then return false, 'The car is gone.' end
    local drop = Config.DropOff
    if #(GetEntityCoords(car) - drop.coords) > drop.radius + 4.0 then return false, 'Bring it into the lot.' end
    if not CivJobs.near(src, drop.coords, drop.radius + 15.0) then return false end
    if os.time() - c.createdAt < Config.MinCaseSeconds then return false, 'That was impossibly fast.' end
    local cond = math.max(0.0, math.min(1.0, GetVehicleBodyHealth(car) / 1000.0))
    local km = #(c.spot - drop.coords) / 1000.0
    local pay = math.floor(Config.Pay.base * (0.5 + 0.5 * cond) + Config.Pay.perKm * km)
    CivJobs.reward(src, JOB, {
        pay = pay,
        xp = Config.XP.recovered,
        label = ('%s %s recovered (%d%% condition)'):format(c.color, c.model, math.floor(cond * 100)),
    })
    clearCase(src, true)
    setStatus(src)
    scheduleCase(src)
    return true
end)

lib.callback.register('bdev-cj-repo:skip', function(src)
    if not cases[src] then return false end
    if skips[src] and os.time() - skips[src] < Config.SkipCooldown then
        return false, ('You can drop another case in %ds.'):format(Config.SkipCooldown - (os.time() - skips[src]))
    end
    skips[src] = os.time()
    clearCase(src, true)
    setStatus(src)
    scheduleCase(src, 5)
    return true
end)

AddEventHandler('playerDropped', function()
    local src = source
    clearCase(src, false)
    skips[src] = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src in pairs(cases) do clearCase(src, false) end
end)
