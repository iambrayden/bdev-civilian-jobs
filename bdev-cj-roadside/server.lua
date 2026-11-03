local JOB = Config.Job.id
local WHEELS = { 0, 1, 4, 5 } -- front left, front right, rear left, rear right

CivJobs.register(Config.Job)

local calls = {}    -- worker src -> call
local npcJobs = {}  -- request id -> { requester, netId, startedAt }
local skips = {}    -- src -> os.time() of last skip
local nextCallId = 0

local ISSUE_LABEL = {
    tire = 'Flat tire', battery = 'Dead battery', fuel = 'Out of fuel', coolant = 'Overheating',
    engine = 'Engine damage', flipped = 'Rolled over', body = 'Body damage', inspect = 'Safety inspection',
}

local function dbg(...) if Config.Debug then print('[roadside]', ...) end end

local function issueList(kinds)
    local list = {}
    for _, kind in ipairs(kinds) do
        if kind == 'tire' then
            local w = WHEELS[math.random(#WHEELS)]
            list[#list + 1] = { key = 'tire_' .. w, kind = 'tire', wheel = w, label = ISSUE_LABEL.tire }
        else
            list[#list + 1] = { key = kind, kind = kind, label = ISSUE_LABEL[kind] or kind }
        end
    end
    return list
end

local function publicCall(c)
    return {
        id = c.id,
        kind = c.kind,
        label = c.label,
        issues = c.issues,
        spot = c.spot,
        model = c.model,
        ped = c.ped,
        line = c.line,
        netId = c.netId,
        diagnosed = c.diagnosed,
        requesterName = c.requesterName,
        note = c.note,
    }
end

local function callVehicle(c)
    return c and c.netId and CivJobs.entity(c.netId)
end

local function deleteNpcEntities(c)
    if not c or c.kind ~= 'npc' then return end
    for _, net in ipairs({ c.netId, c.pedNet }) do
        local ent = CivJobs.entity(net)
        if ent then DeleteEntity(ent) end
    end
end

local function setStatus(src)
    local c = calls[src]
    if not c then return CivJobs.status(src, 'Waiting for the next call…') end
    local pending = 0
    for _, i in ipairs(c.issues) do if not i.done then pending = pending + 1 end end
    if c.kind == 'player' then
        CivJobs.status(src, c.diagnosed
            and ('%s\'s car: %d problem(s) left'):format(c.requesterName, pending)
            or ('Player call: %s'):format(c.requesterName))
    else
        CivJobs.status(src, ('NPC call: %s%s'):format(c.label, c.arrivedAt and (' (%d left)'):format(pending) or ''))
    end
end

local function clearCall(src, notifyClient)
    local c = calls[src]
    if not c then return end
    calls[src] = nil
    deleteNpcEntities(c)
    if notifyClient then TriggerClientEvent('bdev-cj-roadside:client:clearCall', src) end
end

--------------------------------------------------------------------------------
-- NPC calls
--------------------------------------------------------------------------------
local function pickScenario(level)
    local pool, total = {}, 0
    for _, s in ipairs(Config.Scenarios) do
        if (s.minLevel or 1) <= level then
            pool[#pool + 1] = s
            total = total + (s.weight or 1)
        end
    end
    local roll = math.random() * total
    for _, s in ipairs(pool) do
        roll = roll - (s.weight or 1)
        if roll <= 0 then return s end
    end
    return pool[#pool]
end

local function pickSpot(src)
    local pos = CivJobs.coords(src)
    local good = {}
    for _, s in ipairs(Config.Spots) do
        local d = #(pos - s)
        if d >= Config.MinCallDistance and d <= Config.MaxCallDistance then good[#good + 1] = s end
    end
    if #good == 0 then good = Config.Spots end
    return good[math.random(#good)]
end

local function newNpcCall(src)
    if calls[src] or not CivJobs.session(src, JOB) then return end
    local scen = pickScenario(CivJobs.level(src, JOB))
    nextCallId = nextCallId + 1
    local c = {
        id = nextCallId,
        kind = 'npc',
        label = scen.label,
        issues = issueList(scen.issues),
        spot = pickSpot(src),
        model = Config.Models[math.random(#Config.Models)],
        ped = Config.Peds[math.random(#Config.Peds)],
        line = scen.lines and scen.lines[math.random(#scen.lines)] or nil,
        createdAt = os.time(),
        quality = {},
    }
    calls[src] = c
    setStatus(src)
    TriggerClientEvent('bdev-cj-roadside:client:call', src, publicCall(c))
    dbg('npc call', src, c.label)
end

local function scheduleNpcCall(src, delay)
    local d = delay or math.random(Config.NextCallDelay[1], Config.NextCallDelay[2])
    SetTimeout(d * 1000, function()
        if CivJobs.session(src, JOB) and not calls[src] then newNpcCall(src) end
    end)
end

--------------------------------------------------------------------------------
-- Finishing
--------------------------------------------------------------------------------
local function average(list)
    if #list == 0 then return 0.5 end
    local sum = 0
    for _, q in ipairs(list) do sum = sum + q end
    return sum / #list
end

local function finishCall(src)
    local c = calls[src]
    if not c then return end
    calls[src] = nil
    local quality = average(c.quality)

    if c.kind == 'npc' then
        local pay = 0
        for _, i in ipairs(c.issues) do pay = pay + (Config.Pay.issue[i.kind] or 100) end
        local response = (c.arrivedAt or os.time()) - c.createdAt
        local speed = math.max(0.0, math.min(1.0, Config.Pay.responseTarget / math.max(1, response)))
        local tip = math.floor(Config.Pay.tipMax * quality * (0.6 + 0.4 * speed))
        CivJobs.reward(src, JOB, {
            pay = pay + tip,
            xp = Config.XP.call + Config.XP.issue * #c.issues,
            label = ('%s fixed (tip %s%d)'):format(c.label, '$', tip),
        })
        TriggerClientEvent('bdev-cj-roadside:client:callDone', src, c.id, quality)
    else
        CivJobs.completeRequest(c.reqId, {
            pay = Config.Pay.playerIssue * #c.issues,
            xp = Config.XP.call + Config.XP.issue * #c.issues,
            label = 'roadside call',
        })
        TriggerClientEvent('bdev-cj-roadside:client:callDone', src, c.id, quality)
    end
    setStatus(src)
    scheduleNpcCall(src)
end

--------------------------------------------------------------------------------
-- Shift hooks
--------------------------------------------------------------------------------
CivJobs.onStart(JOB, function(src)
    setStatus(src)
    scheduleNpcCall(src, 6)
end)

CivJobs.onStop(JOB, function(src)
    clearCall(src, true)
end)

-- A worker accepted a player's request: drop any NPC call and go help the player.
CivJobs.onRequest(JOB, function(src, req)
    clearCall(src, true)
    nextCallId = nextCallId + 1
    calls[src] = {
        id = nextCallId,
        kind = 'player',
        reqId = req.id,
        label = 'Player call',
        issues = {},
        spot = req.coords,
        netId = req.netId,
        requesterName = req.requesterName,
        requester = req.requester,
        note = req.note,
        createdAt = os.time(),
        quality = {},
    }
    setStatus(src)
    TriggerClientEvent('bdev-cj-roadside:client:call', src, publicCall(calls[src]))
end)

CivJobs.onRequestCancelled(JOB, function(worker, reqId, req)
    if worker and calls[worker] and calls[worker].reqId == reqId then
        clearCall(worker, true)
        setStatus(worker)
        scheduleNpcCall(worker)
    end
    if npcJobs[reqId] then
        TriggerClientEvent('bdev-cj-roadside:client:npcCancel', npcJobs[reqId].requester, reqId)
        npcJobs[reqId] = nil
    elseif not worker and req and req.requester then
        TriggerClientEvent('bdev-cj-roadside:client:npcCancel', req.requester, reqId)
    end
end)

-- Nobody on duty: the requester's own client drives an NPC mechanic out.
CivJobs.onNpcRequest(JOB, function(req)
    if not req.netId then return CivJobs.completeNpcRequest(req.id, false) end
    npcJobs[req.id] = { requester = req.requester, netId = req.netId, startedAt = os.time() }
    TriggerClientEvent('bdev-cj-roadside:client:npcService', req.requester, req.id, req.netId)
end)

--------------------------------------------------------------------------------
-- Worker callbacks
--------------------------------------------------------------------------------
local function workerCall(src, callId)
    local c = calls[src]
    if not c or c.id ~= callId or not CivJobs.session(src, JOB) then return nil end
    return c
end

-- The worker's client spawned the broken-down NPC car + driver.
lib.callback.register('bdev-cj-roadside:spawned', function(src, callId, vehNet, pedNet)
    local c = workerCall(src, callId)
    if not c or c.kind ~= 'npc' then return false end
    if c.netId and callVehicle(c) then return false end -- already has a live car
    local veh = CivJobs.entity(vehNet)
    if not veh or GetEntityModel(veh) ~= joaat(c.model) then return false end
    if #(GetEntityCoords(veh) - vec3(c.spot.x, c.spot.y, c.spot.z)) > 200.0 then return false end
    c.netId, c.pedNet = vehNet, pedNet
    pcall(SetEntityOrphanMode, veh, 2)
    local ped = CivJobs.entity(pedNet)
    if ped then pcall(SetEntityOrphanMode, ped, 2) end
    return true
end)

lib.callback.register('bdev-cj-roadside:arrived', function(src, callId)
    local c = workerCall(src, callId)
    local veh = callVehicle(c)
    if not c or not veh or c.arrivedAt then return false end
    if not CivJobs.near(src, GetEntityCoords(veh), 40.0) then return false end
    c.arrivedAt = os.time()
    c.lastFix = os.time()
    if c.kind == 'player' and GetPlayerName(c.requester) then
        CivJobs.notify(c.requester, 'Your mechanic has arrived. Step out of the car so they can work.', 'success', Config.Job.label)
    end
    setStatus(src)
    return true
end)

-- Player cars: work out what's wrong. Engine/body/fuel/roll are read on the server;
-- burst tires come from the worker's client (the server can't see tire state).
lib.callback.register('bdev-cj-roadside:diagnose', function(src, callId, report)
    local c = workerCall(src, callId)
    local veh = callVehicle(c)
    if not c or c.kind ~= 'player' or not veh then return false, 'The car is gone.' end
    if c.diagnosed then return true, c.issues end
    if not CivJobs.near(src, GetEntityCoords(veh), 6.0) then return false, 'Get closer to the car.' end
    if GetPedInVehicleSeat(veh, -1) ~= 0 then return false, 'Ask the driver to step out first.' end

    local kinds = {}
    local list = {}
    if type(report) == 'table' and type(report.tires) == 'table' then
        local seen = {}
        for _, w in ipairs(report.tires) do
            w = tonumber(w)
            for _, ok in ipairs(WHEELS) do
                if w == ok and not seen[w] then
                    seen[w] = true
                    list[#list + 1] = { key = 'tire_' .. w, kind = 'tire', wheel = w, label = ISSUE_LABEL.tire }
                end
            end
        end
    end
    if GetVehicleEngineHealth(veh) < Config.Thresholds.engine then kinds[#kinds + 1] = 'engine' end
    if GetVehicleBodyHealth(veh) < Config.Thresholds.body then kinds[#kinds + 1] = 'body' end
    local fuel = Entity(veh).state.fuel
    if fuel == nil and type(report) == 'table' then fuel = tonumber(report.fuel) end
    if fuel and fuel < Config.Thresholds.fuel then kinds[#kinds + 1] = 'fuel' end
    local rot = GetEntityRotation(veh)
    if math.abs(rot.y) > 70.0 or math.abs(rot.x) > 70.0 then kinds[#kinds + 1] = 'flipped' end
    for _, i in ipairs(issueList(kinds)) do list[#list + 1] = i end
    if #list == 0 then list = issueList({ 'inspect' }) end

    c.issues = list
    c.diagnosed = true
    c.lastFix = os.time()
    CivJobs.requestWorking(c.reqId)
    if GetPlayerName(c.requester) then
        local names = {}
        for _, i in ipairs(list) do names[#names + 1] = i.label end
        CivJobs.notify(c.requester, 'Diagnosis: ' .. table.concat(names, ', '), 'inform', Config.Job.label)
    end
    setStatus(src)
    TriggerClientEvent('bdev-cj-roadside:client:call', src, publicCall(c))
    return true, list
end)

lib.callback.register('bdev-cj-roadside:fix', function(src, callId, key, quality)
    local c = workerCall(src, callId)
    local veh = callVehicle(c)
    if not c or not veh then return false, 'The car is gone.' end
    if c.kind == 'player' and not c.diagnosed then return false, 'Run diagnostics first.' end
    local issue
    for _, i in ipairs(c.issues) do
        if i.key == key and not i.done then issue = i end
    end
    if not issue then return false end
    local vpos = GetEntityCoords(veh)
    if not CivJobs.near(src, vpos, 7.0) then return false, 'Get closer to the car.' end
    if os.time() - (c.lastFix or c.createdAt) < Config.MinTaskSeconds then return false, 'Slow down, do the job properly.' end
    local truck = CivJobs.vehicle(src)
    if issue.kind == 'battery' and (not truck or #(GetEntityCoords(truck) - vpos) > 12.0) then
        return false, 'Park your truck next to the car to jump it.'
    end
    if issue.kind == 'flipped' and (not truck or #(GetEntityCoords(truck) - vpos) > 25.0) then
        return false, 'Bring your truck closer to winch the car.'
    end

    issue.done = true
    c.lastFix = os.time()
    c.quality[#c.quality + 1] = math.max(0.0, math.min(1.0, tonumber(quality) or 0.5))
    local owner = NetworkGetEntityOwner(veh)
    TriggerClientEvent('bdev-cj-roadside:client:applyFix', owner and owner > 0 and owner or src, c.netId,
        { kind = issue.kind, wheel = issue.wheel, fuel = Config.Repair.fuel, engine = Config.Repair.engine })

    local left = 0
    for _, i in ipairs(c.issues) do if not i.done then left = left + 1 end end
    if left == 0 then
        finishCall(src)
    else
        setStatus(src)
        TriggerClientEvent('bdev-cj-roadside:client:call', src, publicCall(c))
    end
    return true, left
end)

lib.callback.register('bdev-cj-roadside:skip', function(src)
    local c = calls[src]
    if not c or c.kind ~= 'npc' then return false, 'You can only skip NPC calls.' end
    if skips[src] and os.time() - skips[src] < Config.SkipCooldown then
        return false, ('You can skip again in %ds.'):format(Config.SkipCooldown - (os.time() - skips[src]))
    end
    skips[src] = os.time()
    clearCall(src, true)
    setStatus(src)
    scheduleNpcCall(src, 5)
    return true
end)

-- the worker's client lost the NPC car (e.g. it got destroyed): give a new call
lib.callback.register('bdev-cj-roadside:lost', function(src, callId)
    local c = workerCall(src, callId)
    if not c or c.kind ~= 'npc' or not c.netId then return false end
    if callVehicle(c) then return false end -- still exists, just out of the client's range
    clearCall(src, true)
    setStatus(src)
    scheduleNpcCall(src, 5)
    return true
end)

--------------------------------------------------------------------------------
-- NPC mechanic (requester side)
--------------------------------------------------------------------------------
lib.callback.register('bdev-cj-roadside:npcWorking', function(src, reqId)
    local j = npcJobs[reqId]
    if not j or j.requester ~= src then return false end
    j.workingAt = os.time()
    CivJobs.requestWorking(reqId)
    return true
end)

lib.callback.register('bdev-cj-roadside:npcDone', function(src, reqId)
    local j = npcJobs[reqId]
    if not j or j.requester ~= src or not j.workingAt then return false end
    if os.time() - j.workingAt < Config.NpcService.workTime - 2 then return false end
    npcJobs[reqId] = nil
    local veh = CivJobs.entity(j.netId)
    if veh then
        local owner = NetworkGetEntityOwner(veh)
        TriggerClientEvent('bdev-cj-roadside:client:applyFix', owner and owner > 0 and owner or src, j.netId,
            { kind = Config.NpcService.fullRepair and 'full' or 'npc', fuel = Config.Repair.fuel, engine = Config.Repair.engine })
    end
    CivJobs.completeNpcRequest(reqId, veh ~= nil)
    return true
end)

lib.callback.register('bdev-cj-roadside:npcFailed', function(src, reqId)
    local j = npcJobs[reqId]
    if not j or j.requester ~= src then return false end
    npcJobs[reqId] = nil
    CivJobs.completeNpcRequest(reqId, false)
    return true
end)

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------
AddEventHandler('playerDropped', function()
    local src = source
    clearCall(src, false)
    skips[src] = nil
    for id, j in pairs(npcJobs) do
        if j.requester == src then npcJobs[id] = nil end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src in pairs(calls) do clearCall(src, false) end
end)
