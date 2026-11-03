local JOB = Config.Job.id

CivJobs.register(Config.Job)

local trucks = {}    -- vendor src -> truck
local spotSales = {} -- spot index -> { os.time(), ... }
local pairBonus = {} -- 'vendorCid:buyerCid' -> os.time()
local nextOrder = 0

local MENU = {}
for _, m in ipairs(Config.Menu) do MENU[m.id] = m end

local function player(src) return exports.qbx_core:GetPlayer(src) end
local function citizenid(src)
    local p = player(src)
    return p and p.PlayerData.citizenid
end
local function charName(src)
    local p = player(src)
    local ci = p and p.PlayerData.charinfo or {}
    local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    return name ~= '' and name or 'A customer'
end

local function refund(order)
    if order.kind ~= 'player' or not order.total or order.total <= 0 then return end
    local p = player(order.buyer)
    if p and p.PlayerData.citizenid == order.buyerCid then
        p.Functions.AddMoney(order.account or 'bank', order.total, 'foodtruck-refund')
        CivJobs.notify(order.buyer, ('Your food order was cancelled. %s refunded.'):format('$' .. order.total), 'inform', 'Food truck')
    else
        pcall(function() exports.qbx_core:AddMoney(order.buyerCid, order.account or 'bank', order.total, 'foodtruck-refund') end)
    end
end

local function units(order)
    local n = 0
    for _, it in ipairs(order.items) do n = n + it.n end
    return n
end

local function publicOrder(o)
    return { id = o.id, kind = o.kind, items = o.items, buyerName = o.buyerName, ped = o.ped, expiresIn = o.expiresAt - os.time() }
end

local function publicState(t)
    local orders = {}
    for _, o in pairs(t.orders) do orders[#orders + 1] = publicOrder(o) end
    table.sort(orders, function(a, b) return a.id < b.id end)
    return { stock = t.stock, max = Config.Stock.max, open = t.open, spot = t.spotLabel, demand = t.demand, orders = orders }
end

local function push(src)
    local t = trucks[src]
    if t then TriggerClientEvent('bdev-cj-foodtruck:client:state', src, publicState(t)) end
end

local function setStatus(src)
    local t = trucks[src]
    if not t then return end
    CivJobs.status(src, t.open and ('Open at %s · stock %d/%d'):format(t.spotLabel, t.stock, Config.Stock.max)
        or ('Closed · stock %d/%d · park somewhere busy and open up'):format(t.stock, Config.Stock.max))
end

local function menuFor(level)
    local list = {}
    for _, m in ipairs(Config.Menu) do
        if (m.minLevel or 1) <= level then list[#list + 1] = { id = m.id, label = m.label, price = m.price } end
    end
    return list
end

--------------------------------------------------------------------------------
-- Demand
--------------------------------------------------------------------------------
local function spotAt(pos, level)
    local best, bestD
    for i, s in ipairs(Config.Spots) do
        local d = #(pos - s.coords)
        if d <= Config.SpotRadius and (s.minLevel or 1) <= level and (not bestD or d < bestD) then best, bestD = i, d end
    end
    if best then return best, Config.Spots[best].label, Config.Spots[best].demand end
    return nil, 'a quiet street', Config.QuietDemand
end

local function demandOf(src, t)
    local d = t.baseDemand or Config.QuietDemand
    if t.spot then
        local list, now, keep = spotSales[t.spot] or {}, os.time(), {}
        for _, at in ipairs(list) do if now - at < Config.Saturation.window then keep[#keep + 1] = at end end
        spotSales[t.spot] = keep
        d = d * math.max(Config.Saturation.floor, 1.0 - #keep * Config.Saturation.perServe)
    end
    for other, o in pairs(trucks) do
        if other ~= src and o.open and o.pos and #(o.pos - t.pos) < Config.Competition.radius then
            d = d * Config.Competition.factor
            break
        end
    end
    return d
end

--------------------------------------------------------------------------------
-- Open / close
--------------------------------------------------------------------------------
local function setVanState(src, open)
    local van = CivJobs.vehicle(src)
    if van then
        Entity(van).state:set('foodtruck', open and { open = true, owner = src, name = charName(src) } or nil, true)
    end
end

local function close(src, why)
    local t = trucks[src]
    if not t or not t.open then return end
    t.open = false
    for id, o in pairs(t.orders) do
        refund(o)
        t.orders[id] = nil
    end
    setVanState(src, false)
    TriggerClientEvent('bdev-cj-foodtruck:client:closed', src, why)
    push(src)
    setStatus(src)
end

lib.callback.register('bdev-cj-foodtruck:open', function(src)
    local t = trucks[src]
    if not t or t.open or not CivJobs.session(src, JOB) then return false end
    local van = CivJobs.vehicle(src)
    if not van then return false, 'Your truck is gone.' end
    if not CivJobs.near(src, GetEntityCoords(van), 6.0) then return false, 'Stand by your truck.' end
    if GetEntitySpeed(van) > 0.5 then return false, 'Park the truck first.' end
    if t.stock <= 0 then return false, 'You\'re out of supplies. Restock at the commissary.' end
    local level = CivJobs.level(src, JOB)
    t.pos = GetEntityCoords(van)
    t.spot, t.spotLabel, t.baseDemand = spotAt(t.pos, level)
    t.open = true
    t.nextAt = os.time() + 6
    t.demand = demandOf(src, t)
    setVanState(src, true)
    push(src)
    setStatus(src)
    return true, { spot = t.spotLabel, demand = t.demand }
end)

lib.callback.register('bdev-cj-foodtruck:close', function(src)
    close(src, 'closed')
    return true
end)

--------------------------------------------------------------------------------
-- Customers
--------------------------------------------------------------------------------
local function newNpcOrder(src, t)
    local level = CivJobs.level(src, JOB)
    local menu = menuFor(level)
    local want = math.min(math.random(1, Config.Customers.maxItems), t.stock - (t.reserved or 0))
    if want <= 0 then return end
    local counts = {}
    for _ = 1, want do
        local m = menu[math.random(#menu)]
        counts[m.id] = (counts[m.id] or 0) + 1
    end
    local items = {}
    for id, n in pairs(counts) do items[#items + 1] = { id = id, n = n, label = MENU[id].label } end
    nextOrder = nextOrder + 1
    local o = {
        id = nextOrder, kind = 'npc', items = items, createdAt = os.time(),
        expiresAt = os.time() + Config.Customers.patience, ped = Config.Peds[math.random(#Config.Peds)],
    }
    t.orders[o.id] = o
    TriggerClientEvent('bdev-cj-foodtruck:client:order', src, publicOrder(o))
    push(src)
end

CreateThread(function()
    while true do
        Wait(2000)
        local now = os.time()
        for src, t in pairs(trucks) do
            if t.open then
                local van = CivJobs.vehicle(src)
                if not van or #(GetEntityCoords(van) - t.pos) > 6.0 then
                    close(src, 'moved')
                else
                    -- expire orders
                    for id, o in pairs(t.orders) do
                        if now >= o.expiresAt then
                            t.orders[id] = nil
                            refund(o)
                            TriggerClientEvent('bdev-cj-foodtruck:client:orderGone', src, id, 'left')
                            push(src)
                        end
                    end
                    -- new NPC customers
                    local waiting = 0
                    for _, o in pairs(t.orders) do if o.kind == 'npc' then waiting = waiting + 1 end end
                    if waiting < Config.Customers.queue and now >= (t.nextAt or 0) then
                        t.demand = demandOf(src, t)
                        newNpcOrder(src, t)
                        local gap = Config.Customers.every / math.max(0.15, t.demand)
                        t.nextAt = now + math.floor(gap * (0.7 + math.random() * 0.6))
                    end
                end
            end
        end
    end
end)

lib.callback.register('bdev-cj-foodtruck:serve', function(src, orderId, quality)
    local t = trucks[src]
    local o = t and t.orders[orderId]
    if not o or not t.open then return false, 'That order is gone.' end
    local van = CivJobs.vehicle(src)
    if not van or not CivJobs.near(src, GetEntityCoords(van), 6.0) then return false, 'Get back to your truck.' end
    local n = units(o)
    if os.time() - o.createdAt < n * Config.Customers.secondsPerItem then return false, 'Too fast. Cook it properly.' end
    if t.stock < n then return false, 'Not enough supplies for this order.' end
    quality = math.max(0.0, math.min(1.0, tonumber(quality) or 0.5))

    t.orders[orderId] = nil
    t.stock = t.stock - n
    if t.spot then
        spotSales[t.spot] = spotSales[t.spot] or {}
        table.insert(spotSales[t.spot], os.time())
    end

    local total = 0
    for _, it in ipairs(o.items) do total = total + MENU[it.id].price * it.n end

    if o.kind == 'npc' then
        local patienceLeft = math.max(0.0, (o.expiresAt - os.time()) / Config.Customers.patience)
        local tip = math.floor(Config.Customers.tipMax * quality * (0.5 + 0.5 * patienceLeft))
        CivJobs.reward(src, JOB, { pay = total + tip, xp = Config.XP.order, label = ('Order served (tip $%d)'):format(tip) })
    else
        -- a real player: they get the food, the vendor gets their money + a job bonus
        local buyerOnline = player(o.buyer) and citizenid(o.buyer) == o.buyerCid
        if buyerOnline then
            for _, it in ipairs(o.items) do Config.GiveItem(o.buyer, MENU[it.id].item, it.n) end
            CivJobs.notify(o.buyer, 'Your order is ready. Enjoy!', 'success', 'Food truck')
        end
        CivJobs.reward(src, JOB, { pay = o.total, raw = true, task = false, label = ('Paid by %s'):format(o.buyerName) })
        local key = (citizenid(src) or '?') .. ':' .. o.buyerCid
        if not pairBonus[key] or os.time() - pairBonus[key] > 1200 then
            pairBonus[key] = os.time()
            CivJobs.reward(src, JOB, { pay = Config.PlayerBonus, xp = Config.XP.player, label = 'Real customer bonus', playerWork = true })
        end
    end
    TriggerClientEvent('bdev-cj-foodtruck:client:orderGone', src, orderId, 'served')
    if t.stock <= 0 then
        CivJobs.notify(src, 'Out of supplies! Restock at the commissary.', 'error', Config.Job.label)
        close(src, 'empty')
    end
    push(src)
    setStatus(src)
    return true
end)

lib.callback.register('bdev-cj-foodtruck:restock', function(src)
    local t = trucks[src]
    if not t then return false end
    local van = CivJobs.vehicle(src)
    local depot = Config.Job.depot
    if not van or #(GetEntityCoords(van) - vec3(depot.coords.x, depot.coords.y, depot.coords.z)) > depot.radius then
        return false, 'Bring the truck to the commissary to restock.'
    end
    local missing = Config.Stock.max - t.stock
    if missing <= 0 then return false, 'You\'re fully stocked.' end
    local cost = missing * Config.Stock.cost
    local p = player(src)
    if not p or not p.Functions.RemoveMoney('bank', cost, 'foodtruck-supplies') then
        return false, ('Restocking costs $%d.'):format(cost)
    end
    t.stock = Config.Stock.max
    push(src)
    setStatus(src)
    return true, cost
end)

--------------------------------------------------------------------------------
-- Real players buying
--------------------------------------------------------------------------------
local function openTruck(netId)
    local van = CivJobs.entity(netId)
    if not van then return nil end
    local st = Entity(van).state.foodtruck
    local vendor = st and st.owner
    local t = vendor and trucks[vendor]
    if not t or not t.open then return nil end
    return vendor, t, van
end

lib.callback.register('bdev-cj-foodtruck:menu', function(src, netId)
    local vendor = openTruck(netId)
    if not vendor or vendor == src then return false end
    return true, { menu = menuFor(CivJobs.level(vendor, JOB)), vendor = charName(vendor) }
end)

lib.callback.register('bdev-cj-foodtruck:buy', function(src, netId, cart)
    local vendor, t, van = openTruck(netId)
    if not vendor or vendor == src or type(cart) ~= 'table' then return false, 'This truck isn\'t serving right now.' end
    if not CivJobs.near(src, GetEntityCoords(van), 6.0) then return false, 'Walk up to the window.' end
    for _, o in pairs(t.orders) do
        if o.buyer == src then return false, 'You already have an order waiting here.' end
    end
    local allowed = {}
    for _, m in ipairs(menuFor(CivJobs.level(vendor, JOB))) do allowed[m.id] = true end
    local items, total, count = {}, 0, 0
    for id, n in pairs(cart) do
        n = math.floor(tonumber(n) or 0)
        if allowed[id] and n > 0 then
            n = math.min(n, 5)
            items[#items + 1] = { id = id, n = n, label = MENU[id].label }
            total = total + MENU[id].price * n
            count = count + n
        end
    end
    if count == 0 then return false, 'Pick something to order.' end
    if count > 6 then return false, 'That\'s a lot of food. Six items max.' end
    if count > t.stock then return false, 'The truck is running low. Order less.' end
    local p = player(src)
    if not p then return false end
    local account
    for _, acc in ipairs({ 'bank', 'cash' }) do
        if (p.PlayerData.money[acc] or 0) >= total and p.Functions.RemoveMoney(acc, total, 'foodtruck-order') then account = acc break end
    end
    if not account then return false, ('That comes to $%d.'):format(total) end
    nextOrder = nextOrder + 1
    local o = {
        id = nextOrder, kind = 'player', items = items, buyer = src, buyerCid = p.PlayerData.citizenid, buyerName = charName(src),
        total = total, account = account, createdAt = os.time(), expiresAt = os.time() + Config.PlayerOrderTimeout,
    }
    t.orders[o.id] = o
    CivJobs.notify(vendor, ('%s ordered: %s'):format(o.buyerName, (function()
        local parts = {}
        for _, it in ipairs(items) do parts[#parts + 1] = ('%dx %s'):format(it.n, it.label) end
        return table.concat(parts, ', ')
    end)()), 'inform', 'Real customer')
    TriggerClientEvent('bdev-cj-foodtruck:client:order', vendor, publicOrder(o))
    push(vendor)
    return true, total
end)

--------------------------------------------------------------------------------
-- Shift
--------------------------------------------------------------------------------
CivJobs.onStart(JOB, function(src)
    trucks[src] = { stock = Config.Stock.start, orders = {}, open = false }
    push(src)
    setStatus(src)
end)

CivJobs.onStop(JOB, function(src)
    close(src, 'shift')
    trucks[src] = nil
end)

AddEventHandler('playerDropped', function()
    local src = source
    -- a buyer left: drop their orders (refunded to their account)
    for vendor, t in pairs(trucks) do
        for id, o in pairs(t.orders) do
            if o.buyer == src then
                t.orders[id] = nil
                refund(o)
                TriggerClientEvent('bdev-cj-foodtruck:client:orderGone', vendor, id, 'left')
                push(vendor)
            end
        end
    end
end)
