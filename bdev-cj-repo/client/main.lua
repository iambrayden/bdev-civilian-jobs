local JOB = Config.Job.id

local case
local areaBlip, centerBlip, carBlip
local tipBlips = {}
local witnesses = {} -- idx -> ped
local car, attached = nil, false
local busy = false
local flatNet
local areaPoint, carPoint

local MG = CivJobs.minigame

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function radiusBlip(c, r, color, alpha)
    local b = AddBlipForRadius(c.x, c.y, c.z, r + 0.0)
    SetBlipColour(b, color)
    SetBlipAlpha(b, alpha or 90)
    return b
end

local function removeAll()
    CivJobs.removeBlip(areaBlip)
    CivJobs.removeBlip(centerBlip)
    CivJobs.removeBlip(carBlip)
    for _, b in ipairs(tipBlips) do CivJobs.removeBlip(b) end
    areaBlip, centerBlip, carBlip, tipBlips = nil, nil, nil, {}
    if areaPoint then areaPoint:remove() end
    if carPoint then carPoint:remove() end
    areaPoint, carPoint = nil, nil
    for i, p in pairs(witnesses) do
        if DoesEntityExist(p) then exports.ox_target:removeLocalEntity(p) end
        CivJobs.deleteEntity(p)
        witnesses[i] = nil
    end
end

local function clearCase(keepCar)
    removeAll()
    if case and case.netId then
        exports.ox_target:removeEntity(case.netId, { 'repo_unlock', 'repo_hotwire', 'repo_strap', 'repo_deliver' })
    end
    if car and DoesEntityExist(car) and not keepCar then
        if attached then DetachEntity(car, true, true) end
        CivJobs.deleteEntity(car)
    end
    case, car, attached, busy = nil, nil, false, false
end

local function flatbed()
    return CivJobs.vehicle()
end

local function inDropZone(ent)
    return #(GetEntityCoords(ent) - Config.DropOff.coords) <= Config.DropOff.radius
end

local function caseFile()
    if not case then return CivJobs.notify('No open case.', 'error') end
    lib.alertDialog({
        header = 'Repo order',
        content = ('**Owner:** %s  \n**Vehicle:** %s %s  \n**Plate:** %s  \n**Owed:** $%s  \n\nWork the search area, ask around, and scan plates with **%s** from your flatbed.')
            :format(case.owner, case.color, case.model, case.plate, case.owed, Config.ScanKey),
        centered = true,
    })
end
RegisterCommand('repocase', caseFile, false)

--------------------------------------------------------------------------------
-- Witnesses
--------------------------------------------------------------------------------
local function ask(idx)
    if busy or not case then return end
    busy = true
    local ok, tip = lib.callback.await('bdev-cj-repo:ask', false, case.id, idx)
    busy = false
    if not ok then return end
    case.asked[idx] = true
    local lines = {
        ('A %s %s? Yeah, I think I saw one parked over that way.'):format(case.color, case.model),
        ('%s? That guy owes everybody money. Try over there.'):format(case.owner),
        'Maybe? There was a car like that around here earlier...',
    }
    CivJobs.notify(lines[math.random(#lines)], 'inform', 'Witness')
    local b = radiusBlip(tip.center, tip.radius, 5, 110)
    tipBlips[#tipBlips + 1] = b
    if witnesses[idx] then
        exports.ox_target:removeLocalEntity(witnesses[idx])
        TaskWanderStandard(witnesses[idx], 10.0, 10)
    end
end

local function spawnWitnesses()
    for i = 1, case.witnesses do
        if not case.asked[i] then
            local a, r = math.random() * math.pi * 2, math.random() * case.radius * 0.6
            local probe = vec3(case.search.x + math.cos(a) * r, case.search.y + math.sin(a) * r, case.search.z)
            local found, safe = GetSafeCoordForPed(probe.x, probe.y, probe.z, true, 16)
            local at = found and safe or probe
            local p = CivJobs.spawnPed(Config.Peds[math.random(#Config.Peds)], vec3(at.x, at.y, CivJobs.groundZ(at)), math.random(0, 359) + 0.0, 'WORLD_HUMAN_SMOKING')
            if p then
                witnesses[i] = p
                local blip = AddBlipForEntity(p)
                SetBlipSprite(blip, 280)
                SetBlipScale(blip, 0.6)
                SetBlipColour(blip, 5)
                exports.ox_target:addLocalEntity(p, { {
                    name = 'repo_ask', icon = 'fa-solid fa-comments', label = 'Ask about the car',
                    canInteract = function() return case ~= nil and not case.asked[i] and not busy end,
                    onSelect = function() ask(i) end,
                } })
            end
        end
    end
end

--------------------------------------------------------------------------------
-- The car
--------------------------------------------------------------------------------
local function confrontation()
    if not car or not DoesEntityExist(car) then return end
    local myCase = case
    local spot = GetOffsetFromEntityInWorldCoords(car, 10.0, 8.0, 0.0)
    local o = CivJobs.spawnPed(Config.Peds[math.random(#Config.Peds)], vec3(spot.x, spot.y, CivJobs.groundZ(spot)), 0.0)
    if not o then return end
    TaskGoToEntity(o, cache.ped, -1, 2.0, 2.0, 0, 0)
    CivJobs.notify(('%s: "Hey! What do you think you\'re doing with my car?!"'):format(myCase.owner), 'error', 'Owner')
    Wait(2500)
    local p = promise.new()
    lib.registerContext({
        id = 'repo_confront',
        title = ('%s owes $%s'):format(myCase.owner, myCase.owed),
        canClose = false,
        options = {
            { title = 'Show the repo order', description = 'Try to calm them down.', icon = 'file-contract', onSelect = function() p:resolve('order') end },
            { title = 'Let them pay what they owe', description = ('Smaller fee ($%d). They keep the car and the case closes.'):format(Config.Pay.settle), icon = 'money-bill', onSelect = function() p:resolve('settle') end },
            { title = 'Ignore them and keep working', description = 'Risky.', icon = 'hand', onSelect = function() p:resolve('ignore') end },
        },
    })
    lib.showContext('repo_confront')
    local choice = Citizen.Await(p)
    local ok, outcome = lib.callback.await('bdev-cj-repo:confront', false, myCase.id, choice)
    if not ok then return CivJobs.deleteEntity(o) end
    if outcome == 'settled' then
        CivJobs.notify(('%s: "Fine! Here, take your money. Now get away from my car."'):format(myCase.owner), 'inform', 'Owner')
        local c = car
        if attached then DetachEntity(c, true, true) end
        SetVehicleDoorsLocked(c, 1)
        clearCase(true)
        CivJobs.driveAway(o, c, 45000)
    elseif outcome == 'attack' then
        CivJobs.notify(('%s: "You\'re NOT taking my car!"'):format(myCase.owner), 'error', 'Owner')
        SetBlockingOfNonTemporaryEvents(o, false)
        TaskCombatPed(o, cache.ped, 0, 16)
        SetPedKeepTask(o, true)
        SetTimeout(60000, function() CivJobs.deleteEntity(o) end)
    else
        CivJobs.notify(('%s: "...fine. This isn\'t over."'):format(myCase.owner), 'inform', 'Owner')
        TaskWanderStandard(o, 10.0, 10)
        SetTimeout(20000, function() CivJobs.deleteEntity(o) end)
    end
end

local function step(name, res)
    if not res.success then
        if not res.cancelled then CivJobs.notify('Not quite. Try again.', 'error') end
        return false
    end
    local ok, out = lib.callback.await('bdev-cj-repo:step', false, case.id, name, res.quality)
    if not ok then
        if type(out) == 'string' then CivJobs.notify(out, 'error') end
        return false
    end
    if out and out.confront then CreateThread(confrontation) end
    return true
end

local function attach()
    local fb = flatbed()
    if not fb or not car then return end
    NetworkRequestControlOfEntity(car)
    local deadline = GetGameTimer() + 1500
    while not NetworkHasControlOfEntity(car) and GetGameTimer() < deadline do Wait(0) end
    local a = Config.Attach
    AttachEntityToEntity(car, fb, GetEntityBoneIndexByName(fb, 'bodyshell'), a.x, a.y, a.z, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    attached = true
end

local CAR_OPTIONS = {
    {
        name = 'repo_unlock', icon = 'fa-solid fa-unlock', label = 'Slim jim the door', distance = 2.5,
        canInteract = function() return case ~= nil and not case.unlocked and not attached and not busy end,
        onSelect = function()
            busy = true
            CivJobs.playAnim('mini@safe_cracking', 'idle_base', -1, 1)
            local res = MG('slimjim', { title = 'Slim jim the door' })
            ClearPedTasks(cache.ped)
            if step('unlock', res) then
                case.unlocked = true
                SetVehicleDoorsLocked(car, 1)
                CivJobs.notify('Door\'s open. Hotwire it, or strap it to the flatbed.', 'success')
            end
            busy = false
        end,
    },
    {
        name = 'repo_hotwire', icon = 'fa-solid fa-bolt', label = 'Hotwire it', distance = 2.5,
        canInteract = function() return case ~= nil and case.unlocked and not case.hotwired and not attached and not busy end,
        onSelect = function()
            busy = true
            CivJobs.playAnim('mini@repair', 'fixing_a_player', -1, 1)
            local h = Config.Hotwire
            local res = MG('wiring', { mode = 'sequence', title = 'Hotwire the ignition', clamps = h.clamps, terminals = h.terminals, order = h.order, misses = 2 })
            ClearPedTasks(cache.ped)
            if res.shock then
                ApplyDamageToPed(cache.ped, 4, false)
                CivJobs.notify('Zap! Wrong wire.', 'error')
            end
            if step('hotwire', res) then
                case.hotwired = true
                SetVehicleNeedsToBeHotwired(car, false)
                CivJobs.notify(('It\'s running. Drive it to the %s.'):format(Config.DropOff.label), 'success')
                CivJobs.removeBlip(carBlip)
                carBlip = CivJobs.blip(Config.DropOff.coords, Config.DropOff.label, 225, 1, true)
            end
            busy = false
        end,
    },
    {
        name = 'repo_strap', icon = 'fa-solid fa-link', label = 'Strap it to the flatbed', distance = 3.0,
        canInteract = function()
            local fb = flatbed()
            return case ~= nil and not attached and not case.hotwired and not busy and fb ~= nil and car ~= nil
                and #(GetEntityCoords(fb) - GetEntityCoords(car)) < 14.0
        end,
        onSelect = function()
            busy = true
            CivJobs.playAnim('mini@repair', 'fixing_a_player', -1, 1)
            local res = MG('torque', { title = 'Ratchet the four straps', count = 4 })
            ClearPedTasks(cache.ped)
            if step('strap', res) then
                case.strapped = true
                attach()
                CivJobs.notify(('Strapped down. Take it to the %s.'):format(Config.DropOff.label), 'success')
                CivJobs.removeBlip(carBlip)
                carBlip = CivJobs.blip(Config.DropOff.coords, Config.DropOff.label, 225, 1, true)
            end
            busy = false
        end,
    },
    {
        name = 'repo_deliver', icon = 'fa-solid fa-flag-checkered', label = 'Hand it over', distance = 3.0,
        canInteract = function()
            return case ~= nil and (case.hotwired or case.strapped) and car ~= nil and inDropZone(car)
                and not IsPedInAnyVehicle(cache.ped, false)
        end,
        onSelect = function()
            if attached then
                DetachEntity(car, true, true)
                attached = false
                SetVehicleOnGroundProperly(car)
            end
            local ok, msg = lib.callback.await('bdev-cj-repo:deliver', false, case.id)
            if not ok and msg then CivJobs.notify(msg, 'error') end
        end,
    },
}

local function spawnCar()
    local myCase = case
    local v = CivJobs.spawnRoadsideVehicle(myCase.model, vec4(myCase.spot.x, myCase.spot.y, myCase.spot.z, 0.0), { plate = myCase.plate, locked = true })
    if not v or case ~= myCase then return CivJobs.deleteEntity(v) end
    local col = Config.ColorIds[myCase.color] or 0
    SetVehicleColours(v, col, col)
    SetVehicleNeedsToBeHotwired(v, true)
    local netId = VehToNet(v)
    if not lib.callback.await('bdev-cj-repo:spawned', false, myCase.id, netId) or case ~= myCase then
        return CivJobs.deleteEntity(v)
    end
    myCase.netId = netId
    car = v
    exports.ox_target:addEntity(netId, CAR_OPTIONS)
end

--------------------------------------------------------------------------------
-- Plate reader
--------------------------------------------------------------------------------
lib.addKeybind({
    name = 'repo_scan',
    description = 'Repo plate reader',
    defaultKey = Config.ScanKey,
    onPressed = function()
        local fb = flatbed()
        if not case or not fb or cache.vehicle ~= fb then return end
        local pos, fwd = GetEntityCoords(fb), GetEntityForwardVector(fb)
        local best, bestD
        for _, v in ipairs(GetGamePool('CVehicle')) do
            if v ~= fb and v ~= car or (v == car and not attached) then
                local d = #(GetEntityCoords(v) - pos)
                if d < Config.ScanRange and d > 2.0 then
                    local dir = (GetEntityCoords(v) - pos) / d
                    if dir.x * fwd.x + dir.y * fwd.y > 0.7 and (not bestD or d < bestD) then best, bestD = v, d end
                end
            end
        end
        if not best then return CivJobs.notify('Plate reader: nothing in range ahead.', 'inform') end
        local plate = (GetVehicleNumberPlateText(best) or ''):gsub('%s+', '')
        if plate == case.plate then
            PlaySoundFrontend(-1, 'CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET', true)
            CivJobs.notify(('Plate reader: %s  MATCH!'):format(plate), 'success')
            if not case.found and lib.callback.await('bdev-cj-repo:found', false, case.id) then
                case.found = true
                CivJobs.removeBlip(carBlip)
                carBlip = AddBlipForEntity(best)
                SetBlipColour(carBlip, 1)
                SetBlipRoute(carBlip, true)
            end
        else
            CivJobs.notify(('Plate reader: %s  no match'):format(plate), 'inform')
        end
    end,
})

--------------------------------------------------------------------------------
-- Case lifecycle
--------------------------------------------------------------------------------
RegisterNetEvent('bdev-cj-repo:client:case', function(data)
    if not CivJobs.current(JOB) then return end
    clearCase()
    case = data
    areaBlip = radiusBlip(case.search, case.radius, 1, 80)
    centerBlip = CivJobs.blip(case.search, 'Repo search area', 67, 1, true)
    CivJobs.notify(('New case: %s %s, plate %s. /repocase for the file.'):format(case.color, case.model, case.plate), 'inform', Config.Job.label)

    local myCase = case
    areaPoint = lib.points.new({
        coords = case.search, distance = case.radius + 80.0,
        onEnter = function()
            if case ~= myCase or myCase.witnessesSpawned then return end
            myCase.witnessesSpawned = true
            CivJobs.removeBlip(centerBlip)
            centerBlip = nil
            spawnWitnesses()
            CivJobs.notify('You\'re in the search area. Ask around, and scan plates from the flatbed.', 'inform')
        end,
    })
    carPoint = lib.points.new({
        coords = case.spot, distance = 150.0,
        onEnter = function()
            if case ~= myCase or myCase.carSpawned then return end
            myCase.carSpawned = true
            spawnCar()
        end,
    })
end)

RegisterNetEvent('bdev-cj-repo:client:clearCase', function()
    clearCase()
end)

local FLAT_OPTIONS = {
    {
        name = 'repo_file', icon = 'fa-solid fa-file-contract', label = 'Read the case file', distance = 3.0,
        canInteract = function() return case ~= nil end,
        onSelect = caseFile,
    },
    {
        name = 'repo_skip', icon = 'fa-solid fa-forward', label = 'Drop this case', distance = 3.0,
        canInteract = function() return case ~= nil and not busy end,
        onSelect = function()
            local ok, msg = lib.callback.await('bdev-cj-repo:skip', false)
            if ok then CivJobs.notify('Case dropped. The office will send another.', 'inform')
            elseif msg then CivJobs.notify(msg, 'error') end
        end,
    },
}

CivJobs.onStart(JOB, function(session)
    flatNet = session.netId
    if flatNet then exports.ox_target:addEntity(flatNet, FLAT_OPTIONS) end
    CivJobs.notify(('The office will send you a case. Use %s in the flatbed to scan plates.'):format(Config.ScanKey), 'inform', Config.Job.label)
end)

CivJobs.onStop(JOB, function()
    clearCase()
    if flatNet then exports.ox_target:removeEntity(flatNet, { 'repo_file', 'repo_skip' }) end
    flatNet = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearCase() end
end)
