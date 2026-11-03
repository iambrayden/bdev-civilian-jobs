-- Vendor side: open up, NPC customers queue at the window, cook and serve.

local JOB = Config.Job.id

local state = { stock = 0, max = Config.Stock.max, open = false, orders = {} }
local peds = {}     -- order id -> ped
local slots = {}    -- order id -> queue slot
local busy = false
local vanNet

local MENU = {}
for _, m in ipairs(Config.Menu) do MENU[m.id] = m end

local function van()
    return CivJobs.vehicle()
end

local function windowSpot(slot)
    local v = van()
    if not v then return nil end
    local o = Config.WindowOffset
    return GetOffsetFromEntityInWorldCoords(v, o.x + math.max(0, slot - 1) * 0.6, o.y + 1.2 - (slot - 1) * 1.3, o.z)
end

local function freeSlot()
    for s = 1, 6 do
        local taken = false
        for _, v in pairs(slots) do if v == s then taken = true end end
        if not taken then return s end
    end
    return 6
end

local function sendAway(id, delay)
    local p = peds[id]
    peds[id], slots[id] = nil, nil
    if not p or not DoesEntityExist(p) then return end
    ClearPedTasks(p)
    TaskWanderStandard(p, 10.0, 10)
    SetTimeout(delay or 10000, function() CivJobs.deleteEntity(p) end)
end

local function clearPeds()
    for id, p in pairs(peds) do CivJobs.deleteEntity(p) peds[id] = nil end
    slots = {}
end

local function updateUI()
    if state.open then
        lib.showTextUI(('Open at %s · stock %d/%d · %d waiting'):format(state.spot or '?', state.stock, state.max, #state.orders), { position = 'top-center' })
    else
        lib.hideTextUI()
    end
end

local function orderText(o)
    local parts = {}
    for _, it in ipairs(o.items) do parts[#parts + 1] = ('%dx %s'):format(it.n, it.label or it.id) end
    return table.concat(parts, ', ')
end

--------------------------------------------------------------------------------
-- Cooking
--------------------------------------------------------------------------------
local function cook(o)
    local grill, builds = {}, {}
    for _, it in ipairs(o.items) do
        local m = MENU[it.id]
        if m and m.grill then
            for _ = 1, it.n do grill[#grill + 1] = m.grill end
        end
        if m and m.build then builds[#builds + 1] = { label = ('%s%s'):format(m.label, it.n > 1 and (' x' .. it.n) or ''), steps = m.build } end
    end
    local total, n = 0, 0
    TaskStartScenarioInPlace(cache.ped, 'PROP_HUMAN_BBQ', 0, true)
    -- the grill fits 6 at a time
    local i = 1
    while i <= #grill do
        local batch = {}
        for k = i, math.min(i + 5, #grill) do batch[#batch + 1] = grill[k] end
        local res = CivJobs.minigame('grill', { title = 'On the grill', items = batch })
        if not res.success then ClearPedTasks(cache.ped) return false, res end
        total, n = total + res.quality, n + 1
        i = i + 6
    end
    ClearPedTasks(cache.ped)
    for _, b in ipairs(builds) do
        local res = CivJobs.minigame('assemble', { title = 'Build it', label = b.label, steps = b.steps, extra = Config.Distractors })
        if not res.success then return false, res end
        total, n = total + res.quality, n + 1
    end
    return true, n > 0 and total / n or 1.0
end

local function serve(o)
    if busy then return end
    busy = true
    local ok, q = cook(o)
    busy = false
    if not ok then
        if q and not q.cancelled then CivJobs.notify('That order got messed up. Start it again.', 'error') end
        return
    end
    local done, msg = lib.callback.await('bdev-cj-foodtruck:serve', false, o.id, q)
    if not done and msg then CivJobs.notify(msg, 'error') end
end

local function pickOrder()
    if #state.orders == 0 then return CivJobs.notify('Nobody is waiting.', 'inform') end
    local options = {}
    for _, o in ipairs(state.orders) do
        options[#options + 1] = {
            title = (o.kind == 'player' and ('%s (real customer)'):format(o.buyerName or 'Player') or 'Customer') .. ' · ' .. orderText(o),
            description = ('Leaves in %ds'):format(math.max(0, o.expiresIn or 0)),
            icon = o.kind == 'player' and 'user' or 'utensils',
            onSelect = function() serve(o) end,
        }
    end
    table.sort(options, function(a, b) return a.icon == 'user' and b.icon ~= 'user' end)
    lib.registerContext({ id = 'foodtruck_orders', title = 'Orders', options = options })
    lib.showContext('foodtruck_orders')
end

--------------------------------------------------------------------------------
-- Server updates
--------------------------------------------------------------------------------
RegisterNetEvent('bdev-cj-foodtruck:client:state', function(s)
    state = s
    updateUI()
end)

RegisterNetEvent('bdev-cj-foodtruck:client:order', function(o)
    if o.kind == 'player' then
        PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
        return
    end
    local slot = freeSlot()
    slots[o.id] = slot
    local v = van()
    if not v then return end
    local base = GetEntityCoords(v)
    local a = math.random() * math.pi * 2
    local probe = vec3(base.x + math.cos(a) * 18.0, base.y + math.sin(a) * 18.0, base.z)
    local found, safe = GetSafeCoordForPed(probe.x, probe.y, probe.z, true, 16)
    local at = found and safe or probe
    local p = CivJobs.spawnPed(o.ped, vec3(at.x, at.y, CivJobs.groundZ(at)), 0.0)
    if not p then return end
    peds[o.id] = p
    local dest = windowSpot(slot)
    if dest then
        TaskGoStraightToCoord(p, dest.x, dest.y, dest.z, 1.0, 20000, GetEntityHeading(v) + 90.0, 0.3)
    end
end)

RegisterNetEvent('bdev-cj-foodtruck:client:orderGone', function(id, why)
    if why == 'left' and peds[id] then CivJobs.notify('A customer got tired of waiting and left.', 'warning', Config.Job.label) end
    if why == 'served' and peds[id] then
        local lines = { 'Smells amazing, thanks!', 'Perfect, just what I needed.', 'Gracias!', 'Best taco in town.' }
        CivJobs.notify(lines[math.random(#lines)], 'inform', 'Customer')
    end
    sendAway(id)
end)

RegisterNetEvent('bdev-cj-foodtruck:client:closed', function(why)
    clearPeds()
    if why == 'moved' then CivJobs.notify('You drove off, so the truck is closed. Open up again where you park.', 'inform', Config.Job.label)
    elseif why == 'closed' then CivJobs.notify('Closed up.', 'inform', Config.Job.label) end
    lib.hideTextUI()
end)

--------------------------------------------------------------------------------
-- Truck options
--------------------------------------------------------------------------------
local VAN_OPTIONS = {
    {
        name = 'ft_open', icon = 'fa-solid fa-store', label = 'Open for business', distance = 4.0,
        canInteract = function() return not state.open and CivJobs.current(JOB) ~= nil end,
        onSelect = function()
            local ok, res = lib.callback.await('bdev-cj-foodtruck:open', false)
            if not ok then return CivJobs.notify(res or 'Can\'t open here.', 'error') end
            local crowd = res.demand >= 1.3 and 'Busy spot!' or res.demand >= 0.9 and 'Decent crowd.' or 'Pretty quiet here.'
            CivJobs.notify(('Open at %s. %s'):format(res.spot, crowd), 'success', Config.Job.label)
        end,
    },
    {
        name = 'ft_serve', icon = 'fa-solid fa-fire-burner', label = 'Take an order', distance = 4.0,
        canInteract = function() return state.open and not busy end,
        onSelect = pickOrder,
    },
    {
        name = 'ft_close', icon = 'fa-solid fa-door-closed', label = 'Close up', distance = 4.0,
        canInteract = function() return state.open and not busy end,
        onSelect = function() lib.callback.await('bdev-cj-foodtruck:close', false) end,
    },
    {
        name = 'ft_restock', icon = 'fa-solid fa-boxes-stacked', label = ('Restock supplies ($%d each)'):format(Config.Stock.cost), distance = 4.0,
        canInteract = function()
            local d = Config.Job.depot.coords
            return not state.open and state.stock < state.max and #(GetEntityCoords(cache.ped) - vec3(d.x, d.y, d.z)) < Config.Job.depot.radius
        end,
        onSelect = function()
            local ok, res = lib.callback.await('bdev-cj-foodtruck:restock', false)
            if ok then CivJobs.notify(('Restocked for $%d.'):format(res), 'success') else CivJobs.notify(res or 'Can\'t restock.', 'error') end
        end,
    },
}

CivJobs.onStart(JOB, function(session)
    vanNet = session.netId
    if vanNet then exports.ox_target:addEntity(vanNet, VAN_OPTIONS) end
    CivJobs.notify('Drive to a busy spot (beach, Legion Square ...), park and open for business. Check the hot spots in /foodspots.', 'inform', Config.Job.label)
end)

CivJobs.onStop(JOB, function()
    clearPeds()
    lib.hideTextUI()
    if vanNet then exports.ox_target:removeEntity(vanNet, { 'ft_open', 'ft_serve', 'ft_close', 'ft_restock' }) end
    vanNet = nil
    state = { stock = 0, max = Config.Stock.max, open = false, orders = {} }
end)

RegisterCommand('foodspots', function()
    local options = {}
    for _, s in ipairs(Config.Spots) do
        options[#options + 1] = {
            title = s.label,
            description = ('Crowd: %s%s'):format(s.demand >= 1.4 and 'very busy' or s.demand >= 1.2 and 'busy' or 'steady',
                (s.minLevel or 1) > 1 and (' · level %d'):format(s.minLevel) or ''),
            icon = 'location-dot',
            onSelect = function()
                SetNewWaypoint(s.coords.x, s.coords.y)
                CivJobs.notify('GPS set to ' .. s.label, 'success')
            end,
        }
    end
    lib.registerContext({ id = 'foodtruck_spots', title = 'Hot spots', options = options })
    lib.showContext('foodtruck_spots')
end, false)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        clearPeds()
        lib.hideTextUI()
    end
end)
