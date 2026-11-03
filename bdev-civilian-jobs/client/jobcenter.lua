-- Job Center NPC + /jobs menu (works without a phone).

local function levelText(l)
    if not l.next then return ('Level %d (max)'):format(l.level) end
    return ('Level %d  (%d / %d XP)'):format(l.level, l.xp, l.next)
end

local function levelProgress(l)
    if not l.next then return 100 end
    return math.floor((l.xp - l.current) / math.max(1, l.next - l.current) * 100)
end

local function jobOption(j)
    local meta = {
        { label = 'Your level', value = levelText(j.level) },
        { label = 'Jobs done', value = j.completed },
        { label = 'Earned', value = CJ.money(j.earned) },
        { label = 'On shift now', value = j.onDuty },
    }
    if j.vehicle then meta[#meta + 1] = { label = 'Vehicle', value = ('%s (%s deposit)'):format(j.vehicle, CJ.money(j.deposit)) } end
    if j.rating then meta[#meta + 1] = { label = 'Your rating', value = ('%.1f / 5 (%d)'):format(j.rating, j.ratingCount) } end
    return {
        title = j.label .. (j.active and '  (on shift)' or ''),
        description = j.description,
        icon = j.icon or 'briefcase',
        progress = levelProgress(j.level),
        colorScheme = 'green',
        metadata = meta,
        onSelect = function()
            SetNewWaypoint(j.depot.x, j.depot.y)
            CJ.notify(('GPS set to the %s depot.'):format(j.label), 'success')
        end,
    }
end

--- Lists every job that is hiring. With `onlyId`, shows just that job.
function CJ.openJobCenter(onlyId)
    local list = lib.callback.await('bdev-civilian-jobs:overview', false)
    local options = {}
    for _, j in ipairs(list or {}) do
        if not onlyId or j.id == onlyId then options[#options + 1] = jobOption(j) end
    end
    if #options == 0 then return CJ.notify('No jobs are hiring right now.', 'error') end
    lib.registerContext({ id = 'civjobs_center', title = onlyId and options[1].title or 'Job Center', options = options })
    lib.showContext('civjobs_center')
end

if Config.JobCenter.command then
    RegisterCommand(Config.JobCenter.command, function() CJ.openJobCenter() end, false)
end

if Config.JobCenter.enabled then
    local jc = Config.JobCenter
    local ped

    CreateThread(function()
        local b = jc.blip
        local blip = AddBlipForCoord(jc.coords.x, jc.coords.y, jc.coords.z)
        SetBlipSprite(blip, b.sprite)
        SetBlipColour(blip, b.color)
        SetBlipScale(blip, b.scale)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(b.label)
        EndTextCommandSetBlipName(blip)
    end)

    lib.points.new({
        coords = jc.coords.xyz,
        distance = 60.0,
        onEnter = function()
            if ped then return end
            local hash = lib.requestModel(jc.ped)
            ped = CreatePed(4, hash, jc.coords.x, jc.coords.y, jc.coords.z - 1.0, jc.coords.w, false, true)
            SetModelAsNoLongerNeeded(hash)
            SetEntityInvincible(ped, true)
            FreezeEntityPosition(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
            exports.ox_target:addLocalEntity(ped, {
                { name = 'civjobs_center', icon = 'fa-solid fa-briefcase', label = 'Browse jobs', onSelect = function() CJ.openJobCenter() end },
                { name = 'civjobs_service', icon = 'fa-solid fa-phone', label = 'Request a service', onSelect = function() CJ.openServiceMenu() end },
            })
        end,
        onExit = function()
            if ped and DoesEntityExist(ped) then
                exports.ox_target:removeLocalEntity(ped)
                DeletePed(ped)
            end
            ped = nil
        end,
    })

    AddEventHandler('onResourceStop', function(res)
        if res == GetCurrentResourceName() and ped and DoesEntityExist(ped) then DeletePed(ped) end
    end)
end
