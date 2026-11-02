--[[
    Service requests: real players ask for a service (roadside, locksmith, ...).

      open      waiting for an on-duty worker to accept
      assigned  a worker accepted and is on the way
      working   the worker started the job (can't be cancelled any more)
      npc       nobody was available, the job's addon sent an NPC

    The requester pays when they make the request. The money is held by the server and
    goes to the worker when the job's addon calls CompleteRequest. It is refunded if the
    request is cancelled, expires, or the service shuts down.
]]

CJ.Requests = {}

local nextId = 0
local pairBonus = {}      -- 'workerCid:requesterCid' -> os.time() of the last paid bonus
local pendingRatings = {} -- requester src -> { id, workerCid, workerSrc, job, expires }

local function serviceJob(jobId)
    local job = CJ.Jobs[jobId]
    if job and job.requests and CJ.isEnabled(jobId) then return job end
end

function CJ.activeRequestOf(src, jobId)
    for _, r in pairs(CJ.Requests) do
        if r.requester == src and (jobId == nil or r.job == jobId) then return r end
    end
end

local function assignedTo(src)
    for _, r in pairs(CJ.Requests) do
        if r.worker == src then return r end
    end
end

--- Where the job is now: the vehicle if there is one, otherwise the requester.
local function liveCoords(r)
    local ent = r.netId and CJ.entityFromNet(r.netId)
    if ent then return GetEntityCoords(ent) end
    if GetPlayerName(r.requester) then return CJ.playerCoords(r.requester) end
    return r.coords
end

--- What addons get: everything they need to do the job.
local function fullRequest(r)
    return {
        id = r.id,
        job = r.job,
        requester = r.requester,
        requesterName = r.requesterName,
        netId = r.netId,
        plate = r.plate,
        coords = liveCoords(r),
        price = r.price,
        note = r.note,
        status = r.status,
        worker = r.worker,
    }
end

--- What players see in the app / menus.
function CJ.publicRequest(r, viewer)
    local job = CJ.Jobs[r.job]
    local c = liveCoords(r)
    local out = {
        id = r.id,
        job = r.job,
        jobLabel = job and job.label or r.job,
        label = job and job.requests and job.requests.label or r.job,
        status = r.status,
        price = r.price,
        age = os.time() - r.createdAt,
        requesterName = r.requesterName,
        plate = r.plate,
        note = r.note,
        workerName = r.workerName,
        workerRating = r.workerRating,
        mine = viewer == r.requester,
        assignedToMe = viewer ~= nil and viewer == r.worker,
    }
    if viewer and viewer == r.requester and r.worker and GetPlayerName(r.worker) then
        out.workerDistance = math.floor(#(CJ.playerCoords(r.worker) - c))
    elseif viewer and viewer ~= r.requester then
        out.distance = math.floor(#(CJ.playerCoords(viewer) - c))
        out.coords = { x = c.x, y = c.y, z = c.z }
    end
    return out
end

local function refund(r, reason)
    for _, ch in ipairs(r.charges) do
        CJ.addMoney(r.requester, r.requesterCid, ch.account, ch.amount, reason or 'civjobs-request-refund')
    end
    r.charges = {}
end

local function notifyWorkers(jobId, except)
    for _, w in ipairs(CJ.onDuty(jobId)) do
        if w ~= except then TriggerClientEvent('bdev-civilian-jobs:client:requestsChanged', w) end
    end
end

local function remove(r)
    CJ.Requests[r.id] = nil
    notifyWorkers(r.job)
    if GetPlayerName(r.requester) then
        TriggerClientEvent('bdev-civilian-jobs:client:requestsChanged', r.requester)
    end
end

--- Cancels and refunds. `msg` is shown to the requester.
local function cancel(r, msg)
    if not CJ.Requests[r.id] then return end
    local job = CJ.Jobs[r.job]
    refund(r)
    if r.worker then
        if GetPlayerName(r.worker) then
            CJ.notify(r.worker, ('%s cancelled their request.'):format(r.requesterName), 'warning', job and job.label)
            TriggerClientEvent('bdev-civilian-jobs:client:requestCancelled', r.worker, r.job, r.id)
        end
    end
    TriggerEvent('bdev-civilian-jobs:server:requestCancelled', r.worker, r.job, r.id, fullRequest(r))
    if msg and GetPlayerName(r.requester) then
        CJ.phoneNotify(r.requester, job and job.label or 'Service', msg, 'inform')
    end
    remove(r)
end

local function startNpc(r)
    local job = CJ.Jobs[r.job]
    r.status = 'npc'
    r.npcAt = os.time()
    r.worker, r.workerCid, r.workerName = nil, nil, nil
    CJ.phoneNotify(r.requester, job.label,
        ('Nobody was available, so an NPC %s is on the way (%s).'):format(job.requests.label:lower(), CJ.money(r.price)), 'inform')
    TriggerEvent('bdev-civilian-jobs:server:npcRequest', r.job, fullRequest(r))
    notifyWorkers(r.job)
end

--- Switches an unanswered request to an NPC, charging the price difference.
local function tryNpc(r)
    local job = CJ.Jobs[r.job]
    local npcPrice = job and job.requests.npcPrice
    if not npcPrice or not GetPlayerName(r.requester) then return false end
    local extra = npcPrice - r.price
    if extra > 0 then
        local acc = CJ.charge(r.requester, extra, 'civjobs-request-' .. r.job)
        if not acc then
            if not r.npcWarned then
                r.npcWarned = true
                CJ.phoneNotify(r.requester, job.label,
                    ('Still waiting for a worker. An NPC costs %s more, which you can\'t afford right now.'):format(CJ.money(extra)), 'warning')
            end
            return false
        end
        r.charges[#r.charges + 1] = { account = acc, amount = extra }
        r.price = npcPrice
    end
    startNpc(r)
    return true
end

--------------------------------------------------------------------------------
-- Player actions
--------------------------------------------------------------------------------
function CJ.createRequest(src, jobId, note)
    local job = serviceJob(jobId)
    if not job then return false, 'That service is not available.' end
    if CJ.activeRequestOf(src) then return false, 'You already have an open request. Cancel it first.' end
    local s = CJ.Sessions[src]
    if s and s.job == jobId then return false, 'You can\'t request your own job while you are on shift.' end
    local player = CJ.getPlayer(src)
    if not player then return false end
    local rq = job.requests

    local netId, plate
    if rq.needsVehicle then
        local veh = CJ.playerVehicle(src, 6.0)
        if not veh then return false, 'Stand next to the vehicle that needs help.' end
        netId = NetworkGetNetworkIdFromEntity(veh)
        plate = GetVehicleNumberPlateText(veh)
        for _, o in pairs(CJ.Requests) do
            if o.netId == netId then return false, 'Someone already asked for help with this vehicle.' end
        end
        -- don't let people call a service on a worker's own job vehicle
        for _, sess in pairs(CJ.Sessions) do
            if sess.netId == netId then return false, 'That is a job vehicle.' end
        end
    end

    local npc = #CJ.onDuty(jobId) == 0
    if npc and not rq.npcPrice then
        return false, ('Nobody is working as %s right now. Try again later.'):format(job.label)
    end
    local price = npc and rq.npcPrice or rq.price
    local acc = CJ.charge(src, price, 'civjobs-request-' .. jobId)
    if not acc then return false, ('You need %s for this service.'):format(CJ.money(price)) end

    nextId = nextId + 1
    local r = {
        id = nextId,
        job = jobId,
        requester = src,
        requesterCid = player.PlayerData.citizenid,
        requesterName = CJ.charName(src),
        coords = CJ.playerCoords(src),
        netId = netId,
        plate = plate,
        price = price,
        charges = { { account = acc, amount = price } },
        note = type(note) == 'string' and note ~= '' and note:sub(1, 120) or nil,
        createdAt = os.time(),
        status = 'open',
    }
    CJ.Requests[r.id] = r

    if npc then
        startNpc(r)
    else
        CJ.notify(src, ('Request sent. %s is held until the job is done and refunded if nobody comes.'):format(CJ.money(price)),
            'success', job.label)
        for _, w in ipairs(CJ.onDuty(jobId)) do
            local d = math.floor(#(CJ.playerCoords(w) - r.coords))
            CJ.phoneNotify(w, job.label, ('New request from %s, %dm away. Open Gigs or /%s to accept.'):format(
                r.requesterName, d, Config.Requests.queueCommand), 'inform')
        end
        notifyWorkers(jobId)
    end
    return true, CJ.publicRequest(r, src)
end

function CJ.cancelRequest(src)
    local r = CJ.activeRequestOf(src)
    if not r then return false, 'You have no open request.' end
    if r.status == 'working' then return false, 'The worker has already started. You can\'t cancel now.' end
    if r.status == 'npc' and r.npcWorking then return false, 'The NPC has already started working.' end
    cancel(r, 'Request cancelled and refunded.')
    return true
end

function CJ.acceptRequest(src, id)
    local r = CJ.Requests[id]
    if not r or r.status ~= 'open' then return false, 'That request was already taken.' end
    local s = CJ.Sessions[src]
    if not s or s.job ~= r.job then return false, 'You need to be on shift for this job.' end
    if r.requester == src then return false, 'You can\'t take your own request.' end
    if assignedTo(src) then return false, 'Finish your current request first.' end

    local job = CJ.Jobs[r.job]
    r.status = 'assigned'
    r.worker = src
    r.workerCid = s.citizenid
    r.workerName = CJ.charName(src)
    r.assignedAt = os.time()
    r.workerRating = CJ.getRating(r.workerCid, r.job)

    CJ.phoneNotify(r.requester, job.label, ('%s%s accepted your request and is on the way.'):format(
        r.workerName, r.workerRating and (' (%.1f stars)'):format(r.workerRating) or ''), 'success')
    local full = fullRequest(r)
    TriggerEvent('bdev-civilian-jobs:server:requestAccepted', src, r.job, full)
    TriggerClientEvent('bdev-civilian-jobs:client:requestAccepted', src, r.job, full)
    notifyWorkers(r.job, src)
    TriggerClientEvent('bdev-civilian-jobs:client:requestsChanged', r.requester)
    return true, full
end

function CJ.rateRequest(src, id, stars)
    local p = pendingRatings[src]
    stars = math.floor(tonumber(stars) or 0)
    if not p or p.id ~= id or os.time() > p.expires or stars < 1 or stars > 5 then return false end
    pendingRatings[src] = nil
    CJ.addRating(p.workerCid, p.job, stars)
    if GetPlayerName(p.workerSrc) and CJ.citizenid(p.workerSrc) == p.workerCid then
        CJ.notify(p.workerSrc, ('%s rated you %d/5 stars.'):format(CJ.charName(src), stars),
            stars >= 4 and 'success' or 'inform', CJ.Jobs[p.job] and CJ.Jobs[p.job].label)
    end
    return true
end

function CJ.pendingRating(src)
    local p = pendingRatings[src]
    if p and os.time() <= p.expires then return p end
end

--- Open requests a worker can take + the one they're on.
function CJ.requestQueue(src)
    local s = CJ.Sessions[src]
    if not s then return {} end
    local list = {}
    for _, r in pairs(CJ.Requests) do
        if r.job == s.job and (r.status == 'open' or r.worker == src) then
            list[#list + 1] = CJ.publicRequest(r, src)
        end
    end
    table.sort(list, function(a, b)
        if a.assignedToMe ~= b.assignedToMe then return a.assignedToMe end
        return (a.distance or 0) < (b.distance or 0)
    end)
    return list
end

--- Shuts down every request for a job (job disabled / addon stopped).
function CJ.cancelJobRequests(jobId, msg)
    for _, r in pairs(CJ.Requests) do
        if r.job == jobId then cancel(r, msg) end
    end
end

--------------------------------------------------------------------------------
-- Addon API
--------------------------------------------------------------------------------
local function ownedBy(r, invoker)
    local job = r and CJ.Jobs[r.job]
    return job ~= nil and (invoker == nil or invoker == job.resource or invoker == CJ.Resource)
end

exports('GetRequest', function(id)
    local r = CJ.Requests[id]
    return r and fullRequest(r) or nil
end)

--- The worker started on the job; from now on the requester can't cancel.
exports('SetRequestWorking', function(id)
    local r = CJ.Requests[id]
    if not ownedBy(r, GetInvokingResource()) then return false end
    if r.status == 'assigned' then
        r.status = 'working'
        TriggerClientEvent('bdev-civilian-jobs:client:requestsChanged', r.requester)
        return true
    elseif r.status == 'npc' then
        r.npcWorking = true
        return true
    end
    return false
end)

--- Job done by a player worker. Pays the held money + the job's bonus.
--- opts = { pay = extra job-paid amount, xp, label }
exports('CompleteRequest', function(id, opts)
    local r = CJ.Requests[id]
    if not ownedBy(r, GetInvokingResource()) then return false end
    if r.status ~= 'assigned' and r.status ~= 'working' then return false end
    opts = opts or {}
    local job = CJ.Jobs[r.job]
    local worker = r.worker
    CJ.Requests[r.id] = nil

    local s = CJ.Sessions[worker]
    if s and s.job == r.job then
        -- the requester's money: no level bonus, no hourly cap
        CJ.reward(worker, r.job, { pay = r.price, raw = true, task = false, label = ('paid by %s'):format(r.requesterName) })
        local key = r.workerCid .. ':' .. r.requesterCid
        local bonus = (job.requests.bonus or 0) + (tonumber(opts.pay) or 0)
        if pairBonus[key] and os.time() - pairBonus[key] < Config.Requests.pairBonusCooldown then
            bonus = 0
        elseif bonus > 0 then
            pairBonus[key] = os.time()
        end
        CJ.reward(worker, r.job, { pay = bonus, xp = opts.xp or 10, label = opts.label or 'service bonus' })
    else
        CJ.addMoney(worker, r.workerCid, Config.Payment.account, r.price, 'civjobs-request-' .. r.job)
    end

    if GetPlayerName(r.requester) then
        pendingRatings[r.requester] = {
            id = r.id, workerCid = r.workerCid, workerSrc = worker, workerName = r.workerName,
            job = r.job, jobLabel = job.label, expires = os.time() + 600,
        }
        CJ.phoneNotify(r.requester, job.label, ('%s finished the job. Rate them in Gigs.'):format(r.workerName or 'Your worker'), 'success')
        TriggerClientEvent('bdev-civilian-jobs:client:rate', r.requester, { id = r.id, workerName = r.workerName, jobLabel = job.label })
    end
    remove(r)
    return true
end)

--- The worker couldn't finish (left, vehicle gone ...): back into the queue.
exports('ReleaseRequest', function(id, msg)
    local r = CJ.Requests[id]
    if not ownedBy(r, GetInvokingResource()) then return false end
    if r.status ~= 'assigned' and r.status ~= 'working' then return false end
    CJ.releaseRequest(r, msg)
    return true
end)

--- An NPC finished (success = true) or gave up (refund).
exports('CompleteNpcRequest', function(id, success)
    local r = CJ.Requests[id]
    if not ownedBy(r, GetInvokingResource()) or r.status ~= 'npc' then return false end
    local job = CJ.Jobs[r.job]
    if success then
        CJ.phoneNotify(r.requester, job.label, 'All done. Thanks for using ' .. job.label .. '!', 'success')
    else
        refund(r)
        CJ.phoneNotify(r.requester, job.label, 'The NPC couldn\'t finish the job. You have been refunded.', 'error')
    end
    remove(r)
    return true
end)

--- Cancels with refund (e.g. the vehicle was destroyed).
exports('CancelRequest', function(id, msg)
    local r = CJ.Requests[id]
    if not ownedBy(r, GetInvokingResource()) then return false end
    cancel(r, msg or 'Your request was cancelled and refunded.')
    return true
end)

function CJ.releaseRequest(r, msg)
    local job = CJ.Jobs[r.job]
    if r.worker and GetPlayerName(r.worker) then
        TriggerClientEvent('bdev-civilian-jobs:client:requestCancelled', r.worker, r.job, r.id)
    end
    r.status = 'open'
    r.worker, r.workerCid, r.workerName, r.workerRating = nil, nil, nil, nil
    r.createdAt = os.time() -- fresh timers
    CJ.phoneNotify(r.requester, job.label, msg or 'Your worker had to leave. Your request is back in the queue.', 'warning')
    if #CJ.onDuty(r.job) == 0 then
        tryNpc(r)
    else
        notifyWorkers(r.job)
    end
end

--------------------------------------------------------------------------------
-- Callbacks (used by the Gigs app and the /service + /jobqueue menus)
--------------------------------------------------------------------------------
lib.callback.register('bdev-civilian-jobs:request:create', function(src, jobId, note)
    return CJ.createRequest(src, jobId, note)
end)

lib.callback.register('bdev-civilian-jobs:request:cancel', function(src)
    return CJ.cancelRequest(src)
end)

lib.callback.register('bdev-civilian-jobs:request:mine', function(src)
    local r = CJ.activeRequestOf(src)
    return r and CJ.publicRequest(r, src) or nil
end)

lib.callback.register('bdev-civilian-jobs:request:queue', function(src)
    return CJ.requestQueue(src)
end)

lib.callback.register('bdev-civilian-jobs:request:accept', function(src, id)
    return CJ.acceptRequest(src, tonumber(id))
end)

lib.callback.register('bdev-civilian-jobs:request:rate', function(src, id, stars)
    return CJ.rateRequest(src, tonumber(id), stars)
end)

--------------------------------------------------------------------------------
-- Timers & cleanup
--------------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()
        for _, r in pairs(CJ.Requests) do
            local age = now - r.createdAt
            if r.status == 'open' then
                if age >= Config.Requests.expireAfter then
                    cancel(r, 'Nobody took your request in time. You have been refunded.')
                elseif #CJ.onDuty(r.job) == 0 or age >= Config.Requests.npcAfter then
                    tryNpc(r)
                end
            elseif r.status == 'npc' and now - r.npcAt > 600 then
                cancel(r, 'The NPC never made it. You have been refunded.')
            end
        end
    end
end)

-- A worker went off duty mid-request: give the request back to the queue.
AddEventHandler('bdev-civilian-jobs:server:stopped', function(src)
    local r = assignedTo(src)
    if r and CJ.Requests[r.id] then CJ.releaseRequest(r) end
end)

AddEventHandler('playerDropped', function()
    local src = source
    pendingRatings[src] = nil
    local r = CJ.activeRequestOf(src)
    if not r then return end
    if r.status == 'working' and r.worker then
        -- the worker already started: they keep the money, the requester can't dodge paying by leaving
        CJ.addMoney(r.worker, r.workerCid, Config.Payment.account, r.price, 'civjobs-request-' .. r.job)
        if GetPlayerName(r.worker) then
            CJ.notify(r.worker, ('%s left the city. You were paid %s for the call.'):format(r.requesterName, CJ.money(r.price)), 'inform')
            TriggerClientEvent('bdev-civilian-jobs:client:requestCancelled', r.worker, r.job, r.id)
        end
        TriggerEvent('bdev-civilian-jobs:server:requestCancelled', r.worker, r.job, r.id, fullRequest(r))
        remove(r)
    else
        cancel(r)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= CJ.Resource then return end
    for _, r in pairs(CJ.Requests) do refund(r, 'civjobs-request-refund') end
end)
