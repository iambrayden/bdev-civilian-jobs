local JOB = Config.Job.id

CivJobs.register(Config.Job)

local calls = {}   -- worker src -> call
local npcJobs = {} -- request id -> { requester, type, netId, info, workingAt }
local skips = {}
local nextCallId = 0

local STEPS = {
    car = { 'unlock' },
    house = { 'pick' },
    rekey = { 'pick', 'cut' },
    safe = { 'dial' },
    key = { 'cut' },
}
local STEP_LABEL = { unlock = 'Open the car', pick = 'Pick the lock', cut = 'Cut the key', dial = 'Crack the safe' }

local function trim(s)
    local out = tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')
    return out
end

local function citizenid(src)
    local p = exports.qbx_core:GetPlayer(src)
    return p and p.PlayerData.citizenid
end

local function stepList(kind)
    local list = {}
    for _, key in ipairs(STEPS[kind] or {}) do
        list[#list + 1] = { key = key, label = STEP_LABEL[key], done = false }
    end
    return list
end

local function publicCall(c)
    return {
        id = c.id, kind = c.kind, type = c.type, label = c.label, steps = c.steps, spot = c.spot, door = c.door,
        model = c.model, ped = c.ped, line = c.line, netId = c.netId, highSecurity = c.highSecurity,
        requesterName = c.requesterName, note = c.note,
    }
end

local function callPos(c)
    if c.netId then
        local e = CivJobs.entity(c.netId)
        if e then return GetEntityCoords(e) end
        if c.type == 'car' or c.type == 'key' then return nil end
    end
    return vec3(c.spot.x, c.spot.y, c.spot.z)
end

local function setStatus(src)
    local c = calls[src]
    if not c then return CivJobs.status(src, 'Waiting for the next call…') end
    CivJobs.status(src, c.kind == 'player' and ('%s: %s'):format(c.requesterName, c.label) or ('NPC call: %s'):format(c.label))
end

local function deleteNpcEntities(c)
    if not c or c.kind ~= 'npc' then return end
    for _, net in ipairs({ c.netId, c.pedNet }) do
        local e = CivJobs.entity(net)
        if e then DeleteEntity(e) end
    end
end

local function clearCall(src, tell)
    local c = calls[src]
    if not c then return end
    calls[src] = nil
    deleteNpcEntities(c)
    if tell then TriggerClientEvent('bdev-cj-locksmith:client:clearCall', src) end
end

--------------------------------------------------------------------------------
-- What a finished job does for a real player
--------------------------------------------------------------------------------
local function applyEffects(kind, requester, netId, info)
    if kind == 'car' or kind == 'key' then
        local veh = CivJobs.entity(netId)
        if not veh then return false end
        if kind == 'car' then
            local owner = NetworkGetEntityOwner(veh)
            TriggerClientEvent('bdev-cj-locksmith:client:unlock', owner and owner > 0 and owner or requester, netId)
        end
        if GetResourceState('qbx_vehiclekeys') == 'started' and GetPlayerName(requester) then
            pcall(function() exports.qbx_vehiclekeys:GiveKeys(requester, veh, true) end)
        end
        return true
    elseif kind == 'house' then
        if not GetPlayerName(requester) or not info or info.house == nil then return false end
        TriggerClientEvent('bdev-cj-locksmith:client:enterHouse', requester, info.house)
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- Request hooks (called by the base through exports)
--------------------------------------------------------------------------------
exports('ValidateRequest', function(src, typeId, context, netId)
    local cid = citizenid(src)
    if not cid then return false end
    if typeId == 'car' or typeId == 'key' then
        local veh = netId and CivJobs.entity(netId)
        if not veh then return false, 'Stand next to your car.' end
        local plate = trim(GetVehicleNumberPlateText(veh))
        local ok, owns = pcall(Config.OwnsVehicle, cid, plate)
        if not ok or not owns then return false, 'That car isn\'t registered to you.' end
        return true, { plate = plate }
    elseif typeId == 'house' then
        if GetResourceState(Config.Housing.resource) ~= 'started' then return false, 'House lockouts aren\'t available here.' end
        local house = type(context) == 'table' and context.house or nil
        if house == nil then return false, 'Stand at the front door of your house.' end
        local ok, owns = pcall(Config.Housing.ownsHouse, src, house)
        if not ok or not owns then return false, 'You don\'t own or rent that house.' end
        return true, { house = house }
    end
    return false, 'Pick what you need help with.'
end)

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

local function pickNear(src, list)
    local pos = CivJobs.coords(src)
    local good = {}
    for _, p in ipairs(list) do
        local d = #(pos - vec3(p.x, p.y, p.z))
        if d >= Config.MinCallDistance and d <= Config.MaxCallDistance then good[#good + 1] = p end
    end
    if #good == 0 then good = list end
    return good[math.random(#good)]
end

local function newNpcCall(src)
    if calls[src] or not CivJobs.session(src, JOB) then return end
    local level = CivJobs.level(src, JOB)
    local scen = pickScenario(level)
    nextCallId = nextCallId + 1
    local c = {
        id = nextCallId, kind = 'npc', type = scen.id, label = scen.label, steps = stepList(scen.id),
        line = scen.lines and scen.lines[math.random(#scen.lines)] or nil,
        ped = Config.Peds[math.random(#Config.Peds)],
        createdAt = os.time(), quality = {},
    }
    if scen.id == 'car' then
        c.spot = pickNear(src, Config.Spots)
        c.model = Config.Models[math.random(#Config.Models)]
        c.highSecurity = level >= Config.HighSecurity.minLevel and math.random() < Config.HighSecurity.chance
    elseif scen.id == 'house' or scen.id == 'rekey' then
        c.door = pickNear(src, Config.Doors)
        c.spot = vec3(c.door.x, c.door.y, c.door.z)
    elseif scen.id == 'safe' then
        c.spot = vec3(Config.Shop.bench.x, Config.Shop.bench.y, Config.Shop.bench.z)
        c.ped = nil
    elseif scen.id == 'key' then
        c.spot = vec3(Config.Shop.counter.x, Config.Shop.counter.y, Config.Shop.counter.z)
    end
    calls[src] = c
    setStatus(src)
    TriggerClientEvent('bdev-cj-locksmith:client:call', src, publicCall(c))
end

local function scheduleNpcCall(src, delay)
    local d = delay or math.random(Config.NextCallDelay[1], Config.NextCallDelay[2])
    SetTimeout(d * 1000, function()
        if CivJobs.session(src, JOB) and not calls[src] then newNpcCall(src) end
    end)
end

local function average(list)
    if #list == 0 then return 0.5 end
    local s = 0
    for _, q in ipairs(list) do s = s + q end
    return s / #list
end

local function finishCall(src)
    local c = calls[src]
    if not c then return end
    calls[src] = nil
    local quality = average(c.quality)
    if c.kind == 'npc' then
        local response = (c.firstStepAt or os.time()) - c.createdAt
        local speed = math.max(0.0, math.min(1.0, Config.Pay.responseTarget / math.max(1, response)))
        local tip = math.floor(Config.Pay.tipMax * quality * (0.6 + 0.4 * speed))
        CivJobs.reward(src, JOB, {
            pay = (Config.Pay[c.type] or 150) + tip,
            xp = Config.XP.call + Config.XP.step * #c.steps,
            label = ('%s done (tip $%d)'):format(c.label, tip),
        })
    else
        applyEffects(c.type, c.requester, c.netId, c.info)
        CivJobs.completeRequest(c.reqId, {
            pay = Config.Pay.playerStep * #c.steps,
            xp = Config.XP.call + Config.XP.step * #c.steps,
            label = 'locksmith call',
        })
    end
    TriggerClientEvent('bdev-cj-locksmith:client:callDone', src, c.id, quality)
    setStatus(src)
    scheduleNpcCall(src)
end

--------------------------------------------------------------------------------
-- Shift + request hooks
--------------------------------------------------------------------------------
CivJobs.onStart(JOB, function(src)
    setStatus(src)
    scheduleNpcCall(src, 6)
end)

CivJobs.onStop(JOB, function(src)
    clearCall(src, true)
end)

CivJobs.onRequest(JOB, function(src, req)
    clearCall(src, true)
    nextCallId = nextCallId + 1
    calls[src] = {
        id = nextCallId, kind = 'player', reqId = req.id, type = req.type, label = req.typeLabel or 'Locksmith call',
        steps = stepList(req.type), spot = req.coords, netId = req.netId, info = req.info,
        requester = req.requester, requesterName = req.requesterName, note = req.note,
        createdAt = os.time(), quality = {},
    }
    setStatus(src)
    TriggerClientEvent('bdev-cj-locksmith:client:call', src, publicCall(calls[src]))
end)

CivJobs.onRequestCancelled(JOB, function(worker, reqId, req)
    if worker and calls[worker] and calls[worker].reqId == reqId then
        clearCall(worker, true)
        setStatus(worker)
        scheduleNpcCall(worker)
    end
    local requester = (npcJobs[reqId] and npcJobs[reqId].requester) or (req and req.requester)
    npcJobs[reqId] = nil
    if requester then TriggerClientEvent('bdev-cj-locksmith:client:npcCancel', requester, reqId) end
end)

CivJobs.onNpcRequest(JOB, function(req)
    npcJobs[req.id] = { requester = req.requester, type = req.type, netId = req.netId, info = req.info, coords = req.coords }
    TriggerClientEvent('bdev-cj-locksmith:client:npcService', req.requester, req.id, req.type, req.netId, req.coords)
end)

--------------------------------------------------------------------------------
-- Worker callbacks
--------------------------------------------------------------------------------
local function workerCall(src, callId)
    local c = calls[src]
    if not c or c.id ~= callId or not CivJobs.session(src, JOB) then return nil end
    return c
end

lib.callback.register('bdev-cj-locksmith:spawned', function(src, callId, vehNet, pedNet)
    local c = workerCall(src, callId)
    if not c or c.kind ~= 'npc' then return false end
    if vehNet then
        if c.type ~= 'car' or (c.netId and CivJobs.entity(c.netId)) then return false end
        local veh = CivJobs.entity(vehNet)
        if not veh or GetEntityModel(veh) ~= joaat(c.model) then return false end
        if #(GetEntityCoords(veh) - vec3(c.spot.x, c.spot.y, c.spot.z)) > 200.0 then return false end
        c.netId = vehNet
        pcall(SetEntityOrphanMode, veh, 2)
    end
    if pedNet then
        local ped = CivJobs.entity(pedNet)
        if ped then
            c.pedNet = pedNet
            pcall(SetEntityOrphanMode, ped, 2)
        end
    end
    return true
end)

lib.callback.register('bdev-cj-locksmith:step', function(src, callId, key, quality)
    local c = workerCall(src, callId)
    if not c then return false end
    local step
    for _, s in ipairs(c.steps) do
        if s.key == key and not s.done then step = s break end
        if not s.done then return false, 'Do the steps in order.' end
    end
    if not step then return false end
    local pos = callPos(c)
    if not pos then return false, 'The car is gone.' end
    if not CivJobs.near(src, pos, 6.0) then return false, 'Get closer.' end
    if c.lastStep and os.time() - c.lastStep < Config.MinStepSeconds then return false, 'Slow down, do it properly.' end
    if c.kind == 'player' and c.type == 'house' and GetPlayerName(c.requester) and not CivJobs.near(c.requester, pos, 25.0) then
        return false, 'The owner needs to be at the door.'
    end
    step.done = true
    c.lastStep = os.time()
    c.firstStepAt = c.firstStepAt or os.time()
    c.quality[#c.quality + 1] = math.max(0.0, math.min(1.0, tonumber(quality) or 0.5))
    if c.kind == 'player' and c.reqId then CivJobs.requestWorking(c.reqId) end

    local left = 0
    for _, s in ipairs(c.steps) do if not s.done then left = left + 1 end end
    if left == 0 then finishCall(src) end
    return true, left
end)

lib.callback.register('bdev-cj-locksmith:skip', function(src)
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

--------------------------------------------------------------------------------
-- NPC locksmith (requester side)
--------------------------------------------------------------------------------
lib.callback.register('bdev-cj-locksmith:npcWorking', function(src, reqId)
    local j = npcJobs[reqId]
    if not j or j.requester ~= src then return false end
    j.workingAt = os.time()
    CivJobs.requestWorking(reqId)
    return true
end)

lib.callback.register('bdev-cj-locksmith:npcDone', function(src, reqId)
    local j = npcJobs[reqId]
    if not j or j.requester ~= src or not j.workingAt then return false end
    if os.time() - j.workingAt < Config.NpcService.workTime - 2 then return false end
    npcJobs[reqId] = nil
    local ok = applyEffects(j.type, src, j.netId, j.info)
    CivJobs.completeNpcRequest(reqId, ok)
    return ok
end)

lib.callback.register('bdev-cj-locksmith:npcFailed', function(src, reqId)
    local j = npcJobs[reqId]
    if not j or j.requester ~= src then return false end
    npcJobs[reqId] = nil
    CivJobs.completeNpcRequest(reqId, false)
    return true
end)

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
