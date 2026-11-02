-- Depot NPC + blip for every enabled job. Rebuilt whenever jobs are added, removed or toggled.

local built = {} -- id -> { blip, point, ped, sig }

local function signature(job)
    local c = job.depot.coords
    return ('%s|%s|%.2f|%.2f|%.2f|%s|%s'):format(job.label, job.depot.ped or '', c.x, c.y, c.z,
        job.vehicle and job.vehicle.deposit or 0, job.enabled and 1 or 0)
end

local function removePed(d)
    if d.ped and DoesEntityExist(d.ped) then
        exports.ox_target:removeLocalEntity(d.ped)
        DeletePed(d.ped)
    end
    d.ped = nil
end

local function deleteDepot(id)
    local d = built[id]
    if not d then return end
    if d.blip and DoesBlipExist(d.blip) then RemoveBlip(d.blip) end
    if d.point then d.point:remove() end
    removePed(d)
    built[id] = nil
end

local function targetOptions(job)
    return {
        {
            name = 'civjobs_start',
            icon = 'fa-solid fa-briefcase',
            label = job.vehicle and ('Start shift (%s deposit)'):format(CJ.money(job.vehicle.deposit)) or 'Start shift',
            canInteract = function() return CJ.Current == nil end,
            onSelect = function() CJ.startJob(job.id) end,
        },
        {
            name = 'civjobs_stop',
            icon = 'fa-solid fa-right-from-bracket',
            label = job.vehicle and 'End shift & return vehicle' or 'End shift',
            canInteract = function() return CJ.Current ~= nil and CJ.Current.job == job.id end,
            onSelect = function() CJ.stopJob() end,
        },
        {
            name = 'civjobs_info',
            icon = 'fa-solid fa-circle-info',
            label = 'About this job',
            onSelect = function() CJ.openJobCenter(job.id) end,
        },
    }
end

local function spawnPed(d, job)
    local model = job.depot.ped or 's_m_m_dockwork_01'
    local ok, hash = pcall(lib.requestModel, model, 10000)
    if not ok or not hash then return print(('[civjobs] bad depot ped model for %s: %s'):format(job.id, model)) end
    local c = job.depot.coords
    local ped = CreatePed(4, hash, c.x, c.y, c.z - 1.0, c.w, false, true)
    SetModelAsNoLongerNeeded(hash)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_CLIPBOARD', 0, true)
    exports.ox_target:addLocalEntity(ped, targetOptions(job))
    d.ped = ped
end

local function buildDepot(job)
    local d = { sig = signature(job) }
    built[job.id] = d
    local b = job.depot.blip
    if b ~= false then
        b = b or {}
        local c = job.depot.coords
        local blip = AddBlipForCoord(c.x, c.y, c.z)
        SetBlipSprite(blip, b.sprite or 280)
        SetBlipColour(blip, b.color or 0)
        SetBlipScale(blip, b.scale or 0.8)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(b.label or job.label)
        EndTextCommandSetBlipName(blip)
        d.blip = blip
    end
    d.point = lib.points.new({
        coords = job.depot.coords.xyz,
        distance = 60.0,
        onEnter = function()
            if built[job.id] == d and not d.ped then spawnPed(d, job) end
        end,
        onExit = function() removePed(d) end,
    })
end

local function sync(jobs)
    jobs = jobs or {}
    for id, d in pairs(built) do
        local job = jobs[id]
        if not job or not job.enabled or signature(job) ~= d.sig then deleteDepot(id) end
    end
    for id, job in pairs(jobs) do
        if job.enabled and not built[id] then buildDepot(job) end
    end
end

AddStateBagChangeHandler('civjobs', 'global', function(_, _, value)
    SetTimeout(0, function() sync(value) end)
end)

CreateThread(function()
    sync(GlobalState.civjobs)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(built) do deleteDepot(id) end
end)
