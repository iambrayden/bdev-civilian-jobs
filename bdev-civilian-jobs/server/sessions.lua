-- Shifts: starting / ending work, the rental vehicle + deposit, and paying players.

CJ.Sessions = {} -- src -> session

local starting = {}  -- src -> true while a start is in progress
local lastStart = {} -- src -> os.time()
local earnings = {}  -- citizenid -> job -> { since, amount } (rolling hourly cap)

function CJ.publicSession(s)
    return {
        job = s.job,
        netId = s.netId,
        startedAt = s.startedAt,
        earned = s.earned,
        tasks = s.tasks,
        level = s.level,
        deposit = s.deposit,
    }
end

function CJ.onDuty(jobId)
    local list = {}
    for src, s in pairs(CJ.Sessions) do
        if s.job == jobId then list[#list + 1] = src end
    end
    return list
end

local function pickSpawn(spawns)
    for _, c in ipairs(spawns) do
        if CJ.spawnClear(c, 3.5) then return c end
    end
end

function CJ.startSession(src, jobId)
    local job = CJ.Jobs[jobId]
    if not job or not CJ.isEnabled(jobId) then return false, 'That job is not hiring right now.' end
    if CJ.Sessions[src] or starting[src] then return false, 'You are already on a shift. End it first.' end
    local player = CJ.getPlayer(src)
    if not player then return false end
    if not CJ.near(CJ.playerCoords(src), job.depot.coords, Config.Limits.depotDistance + 2.0) then
        return false, 'Go to the depot to start a shift.'
    end
    local now = os.time()
    if lastStart[src] and now - lastStart[src] < Config.Limits.startCooldown then
        return false, ('Wait %ds before starting another shift.'):format(Config.Limits.startCooldown - (now - lastStart[src]))
    end
    if CJ.activeRequestOf and CJ.activeRequestOf(src, jobId) then
        return false, 'You have an open request for this service. Cancel it first.'
    end

    starting[src] = true
    local cid = player.PlayerData.citizenid
    local session = {
        job = jobId,
        citizenid = cid,
        startedAt = now,
        earned = 0,
        tasks = 0,
        deposit = 0,
        lastReward = 0,
        level = CJ.levelFromXp(CJ.getStats(cid, jobId).xp),
    }

    if job.vehicle then
        local spawn = pickSpawn(job.vehicle.spawns)
        if not spawn then
            starting[src] = nil
            return false, 'The vehicle bay is blocked. Try again in a moment.'
        end
        local deposit = job.vehicle.deposit or 0
        local acc = CJ.charge(src, deposit, 'civjobs-deposit')
        if not acc then
            starting[src] = nil
            return false, ('You need %s for the vehicle deposit.'):format(CJ.money(deposit))
        end
        local plate = CJ.plate(job.vehicle.plate)
        local netId, veh = CJ.spawnVehicle(job.vehicle.model, spawn, { plate = plate }, GetPlayerPed(src))
        if not netId then
            CJ.addMoney(src, cid, acc, deposit, 'civjobs-deposit-refund')
            starting[src] = nil
            return false, 'Could not get the work vehicle out. Try again.'
        end
        Config.SetFuel(veh, 100.0)
        Config.GiveKeys(src, veh, plate)
        session.netId, session.deposit, session.depositAccount, session.plate = netId, deposit, acc, plate
    end

    starting[src] = nil
    -- the job could have been disabled while the vehicle spawned
    if not CJ.Jobs[jobId] or not CJ.isEnabled(jobId) or not CJ.getPlayer(src) then
        if session.netId then CJ.deleteNet(session.netId) end
        CJ.addMoney(src, cid, session.depositAccount or 'bank', session.deposit, 'civjobs-deposit-refund')
        return false, 'That job is not hiring right now.'
    end

    lastStart[src] = now
    CJ.Sessions[src] = session
    Player(src).state:set('civjob', jobId, true)

    local pub = CJ.publicSession(session)
    TriggerEvent('bdev-civilian-jobs:server:started', src, jobId, pub)
    TriggerClientEvent('bdev-civilian-jobs:client:started', src, jobId, pub)
    CJ.notify(src, job.vehicle
        and ('Shift started. Your %s is ready (%s deposit, refunded when you bring it back).'):format(job.vehicle.label, CJ.money(session.deposit))
        or 'Shift started.', 'success', job.label)
    return true
end

--- reason: 'quit' | 'disabled' | 'unavailable' | 'disconnect' | 'logout' | 'shutdown' | 'addon'
function CJ.endSession(src, reason)
    local s = CJ.Sessions[src]
    if not s then return nil end
    CJ.Sessions[src] = nil
    local job = CJ.Jobs[s.job]

    local refund = 0
    if s.netId then
        local veh = CJ.entityFromNet(s.netId)
        if s.deposit > 0 then
            if reason == 'quit' or reason == 'addon' then
                if veh and job and CJ.near(GetEntityCoords(veh), job.depot.coords, job.depot.radius) then
                    refund = s.deposit
                    if Config.DamageRefund then
                        local cond = math.min(GetVehicleBodyHealth(veh), GetVehicleEngineHealth(veh)) / 1000.0
                        if cond < 0.9 then refund = math.floor(s.deposit * CJ.clamp(cond, 0.0, 1.0)) end
                    end
                end
            elseif reason ~= 'disconnect' and reason ~= 'logout' or Config.RefundOnDisconnect then
                refund = s.deposit
            end
        end
        CJ.deleteNet(s.netId)
    end
    if refund > 0 then
        CJ.addMoney(src, s.citizenid, s.depositAccount or 'bank', refund, 'civjobs-deposit-refund')
    end

    if GetPlayerName(src) then
        Player(src).state:set('civjob', nil, true)
        TriggerClientEvent('bdev-civilian-jobs:client:stopped', src, s.job, reason)
        local label = job and job.label or s.job
        local lines = {
            ('Shift over after %s.'):format(CJ.duration(os.time() - s.startedAt)),
            ('Earned %s from %d job(s).'):format(CJ.money(s.earned), s.tasks),
        }
        if s.deposit > 0 then
            lines[#lines + 1] = refund > 0 and ('Deposit refunded: %s.'):format(CJ.money(refund))
                or 'Deposit kept: the vehicle was not returned to the depot.'
        end
        if reason == 'disabled' or reason == 'unavailable' then
            lines[1] = 'This job was closed by the city. ' .. lines[1]
        end
        CJ.notify(src, table.concat(lines, ' '), 'inform', label)
    end
    TriggerEvent('bdev-civilian-jobs:server:stopped', src, s.job, reason)
    return s, refund
end

function CJ.endJobSessions(jobId, reason)
    for src, s in pairs(CJ.Sessions) do
        if s.job == jobId then CJ.endSession(src, reason) end
    end
end

--------------------------------------------------------------------------------
-- Pay
--------------------------------------------------------------------------------

--- Pays a worker for a finished task. opts = { pay, xp, label, task = true|false, raw = true, playerWork = true }
--- `raw` skips the level bonus and the cap (money that came from another player).
--- `playerWork` = work done for a real player: pays Config.Requests.playerPayMultiplier more and skips the cap.
function CJ.reward(src, jobId, opts, invoker)
    local s = CJ.Sessions[src]
    if not s or s.job ~= jobId then return 0 end
    local job = CJ.Jobs[jobId]
    if not job then return 0 end
    if invoker and invoker ~= job.resource and invoker ~= CJ.Resource then
        print(('^1[civjobs] %s tried to pay for job "%s", which belongs to %s^0'):format(invoker, jobId, job.resource))
        return 0
    end
    opts = opts or {}

    if not opts.raw then
        local now = GetGameTimer()
        if now - s.lastReward < Config.Limits.minRewardGap * 1000 then return 0 end
        s.lastReward = now
    end

    local mult = opts.raw and 1.0 or CJ.payMultiplier(s.level)
    if opts.playerWork and not opts.raw then mult = mult * (Config.Requests.playerPayMultiplier or 1.0) end
    local pay = math.max(0, math.floor((tonumber(opts.pay) or 0) * mult))

    -- rolling hourly cap per player + job (not for money from other players or work done for them)
    local capped = false
    if not opts.raw and not opts.playerWork then
        earnings[s.citizenid] = earnings[s.citizenid] or {}
        local e = earnings[s.citizenid][jobId]
        if not e or os.time() - e.since >= 3600 then
            e = { since = os.time(), amount = 0 }
            earnings[s.citizenid][jobId] = e
        end
        local cap = job.maxEarnPerHour or Config.Limits.maxEarnPerHour
        local room = math.max(0, cap - e.amount)
        if pay > room then pay, capped = room, true end
        e.amount = e.amount + pay
    end

    local player = CJ.getPlayer(src)
    if pay > 0 and player then
        player.Functions.AddMoney(Config.Payment.account, pay, 'civjobs-' .. jobId)
    end

    local xp = math.max(0, math.floor(tonumber(opts.xp) or 0))
    local task = opts.task == false and 0 or 1
    s.earned = s.earned + pay
    s.tasks = s.tasks + task
    local before, after = CJ.addStats(s.citizenid, jobId, xp, pay, task)

    if pay > 0 then
        CJ.notify(src, ('+%s  %s'):format(CJ.money(pay), opts.label or ''), 'success', job.label)
    end
    if capped then
        CJ.notify(src, 'You have hit the hourly pay limit for this job. Keep going for XP or take a break.', 'warning', job.label)
    end
    if after > before then
        s.level = after
        CJ.phoneNotify(src, job.label, ('Level up! You are now level %d (+%d%% pay).'):format(after,
            math.floor((CJ.payMultiplier(after) - 1) * 100 + 0.5)), 'success')
    end
    TriggerClientEvent('bdev-civilian-jobs:client:session', src, CJ.publicSession(s))
    return pay
end

--------------------------------------------------------------------------------
-- Callbacks, commands & exports
--------------------------------------------------------------------------------
lib.callback.register('bdev-civilian-jobs:start', function(src, jobId)
    return CJ.startSession(src, jobId)
end)

lib.callback.register('bdev-civilian-jobs:stop', function(src)
    if not CJ.Sessions[src] then return false, 'You are not on a shift.' end
    CJ.endSession(src, 'quit')
    return true
end)

lib.addCommand('quitjob', {
    help = 'End your civilian job shift (the deposit is only refunded if the vehicle is back at the depot)',
}, function(source)
    if not CJ.Sessions[source] then return CJ.notify(source, 'You are not on a shift.', 'error') end
    CJ.endSession(source, 'quit')
end)

exports('GetSession', function(src)
    local s = CJ.Sessions[src]
    return s and CJ.publicSession(s) or nil
end)

exports('Reward', function(src, jobId, opts)
    return CJ.reward(src, jobId, opts, GetInvokingResource())
end)

exports('EndSession', function(src, reason)
    local s = CJ.Sessions[src]
    if not s then return false end
    local job = CJ.Jobs[s.job]
    local invoker = GetInvokingResource()
    if invoker and job and invoker ~= job.resource then return false end
    CJ.endSession(src, reason == 'quit' and 'quit' or 'addon')
    return true
end)

exports('GetOnDuty', function(jobId) return CJ.onDuty(jobId) end)

exports('GetLevel', function(src, jobId)
    local cid = CJ.citizenid(src)
    if not cid then return 1 end
    return CJ.levelFromXp(CJ.getStats(cid, jobId).xp)
end)

AddEventHandler('playerDropped', function()
    local src = source
    CJ.endSession(src, 'disconnect')
    lastStart[src] = nil
    starting[src] = nil
end)

-- server-side only (qbx triggers it with the player's source); not a net event,
-- so clients can't end other players' shifts with it
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    if type(src) == 'number' then CJ.endSession(src, 'logout') end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= CJ.Resource then return end
    for src in pairs(CJ.Sessions) do CJ.endSession(src, 'shutdown') end
end)
