-- Data for the Gigs phone app and the job center menu.

CJ.ShiftStatus = {} -- src -> short text set by the job addon ("Flat tire on Vespucci Blvd")

local function overview(src)
    local cid = CJ.citizenid(src)
    local s = CJ.Sessions[src]
    local jobs = {}
    for id, job in pairs(CJ.Jobs) do
        if CJ.isEnabled(id) then
            local st = cid and CJ.getStats(cid, id) or { xp = 0, completed = 0, earned = 0 }
            local rating, count
            if cid then rating, count = CJ.getRating(cid, id) end
            jobs[#jobs + 1] = {
                id = id,
                label = job.label,
                description = job.description,
                icon = job.icon,
                depot = { x = job.depot.coords.x, y = job.depot.coords.y, z = job.depot.coords.z },
                deposit = job.vehicle and job.vehicle.deposit or 0,
                vehicle = job.vehicle and job.vehicle.label or nil,
                level = CJ.levelInfo(st.xp),
                completed = st.completed,
                earned = st.earned,
                rating = rating,
                ratingCount = count or 0,
                active = s ~= nil and s.job == id,
                onDuty = #CJ.onDuty(id),
                requests = job.requests and {
                    label = job.requests.label,
                    description = job.requests.description,
                    price = job.requests.price,
                    npcPrice = job.requests.npcPrice,
                    needsVehicle = job.requests.needsVehicle,
                } or nil,
            }
        end
    end
    table.sort(jobs, function(a, b) return a.label < b.label end)
    return jobs
end

lib.callback.register('bdev-civilian-jobs:overview', function(src)
    return overview(src)
end)

lib.callback.register('bdev-civilian-jobs:app:data', function(src)
    local shift
    local s = CJ.Sessions[src]
    if s then
        local job = CJ.Jobs[s.job]
        shift = {
            job = s.job,
            label = job and job.label or s.job,
            duration = os.time() - s.startedAt,
            earned = s.earned,
            tasks = s.tasks,
            level = CJ.levelInfo(CJ.getStats(s.citizenid, s.job).xp),
            deposit = s.deposit,
            vehicle = job and job.vehicle and job.vehicle.label or nil,
            status = CJ.ShiftStatus[src],
            takesRequests = job ~= nil and job.requests ~= nil,
            queue = job and job.requests and CJ.requestQueue(src) or nil,
        }
    end
    local mine = CJ.activeRequestOf(src)
    local rate = CJ.pendingRating(src)
    return {
        name = CJ.charName(src),
        jobs = overview(src),
        shift = shift,
        request = mine and CJ.publicRequest(mine, src) or nil,
        rating = rate and { id = rate.id, workerName = rate.workerName, jobLabel = rate.jobLabel } or nil,
    }
end)

lib.callback.register('bdev-civilian-jobs:app:endShift', function(src)
    if not CJ.Sessions[src] then return false, 'You are not on a shift.' end
    CJ.endSession(src, 'quit')
    return true
end)

exports('SetShiftStatus', function(src, text)
    local s = CJ.Sessions[src]
    local job = s and CJ.Jobs[s.job]
    local invoker = GetInvokingResource()
    if not job or (invoker and invoker ~= job.resource) then return false end
    CJ.ShiftStatus[src] = type(text) == 'string' and text:sub(1, 120) or nil
    return true
end)

AddEventHandler('bdev-civilian-jobs:server:stopped', function(src)
    CJ.ShiftStatus[src] = nil
end)
