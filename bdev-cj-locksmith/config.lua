Config = {}

Config.Debug = false

--------------------------------------------------------------------------------
-- Job definition (sent to bdev-civilian-jobs). Turn it on/off there with /civjobs.
--------------------------------------------------------------------------------
Config.Job = {
    id = 'locksmith',
    label = 'Locksmith',
    description = 'Get people back into their cars and homes, pick locks, crack stuck safes and cut keys. Real players can call you; NPC calls fill the gaps.',
    icon = 'key',
    depot = {
        coords = vec4(170.85, -1722.45, 29.29, 230.0), -- check this spot on your map (/civjobs pos)
        ped = 's_m_m_lathandy_01',
        blip = { sprite = 134, color = 46, scale = 0.8, label = 'Locksmith' },
        radius = 40.0,
    },
    vehicle = {
        model = 'speedo',
        label = 'Locksmith Van',
        deposit = 400,
        plate = 'LOCK',
        spawns = {
            vec4(160.20, -1730.10, 29.29, 140.0),
            vec4(156.40, -1734.70, 29.29, 140.0),
        },
    },
    maxEarnPerHour = 20000,

    requests = {
        label = 'Locksmith',
        description = 'Locked out of your car or house, or need a spare car key?',
        bonus = 100,
        context = 'RequestContext',   -- client export in this resource (which house you're at)
        validate = 'ValidateRequest', -- server export in this resource (do you own it?)
        types = {
            { id = 'car', label = 'Locked out of my car', description = 'Stand next to your car.', price = 250, npcPrice = 400, needsVehicle = true },
            { id = 'house', label = 'Locked out of my house', description = 'Stand at your front door.', price = 300, npcPrice = 450 },
            { id = 'key', label = 'Spare car key', description = 'Stand next to your car.', price = 200, npcPrice = 350, needsVehicle = true },
        },
    },
}

--------------------------------------------------------------------------------
-- Pay for NPC calls (player calls pay what the caller paid + the bonus above + playerStep per step)
--------------------------------------------------------------------------------
Config.Pay = {
    car = 220, house = 260, rekey = 340, safe = 380, key = 160,
    tipMax = 200,
    responseTarget = 240, -- seconds from call to first work for the full speed part of the tip
    playerStep = 50,
}
Config.XP = { step = 6, call = 10 }
Config.MinStepSeconds = 6
Config.NextCallDelay = { 8, 20 }
Config.SkipCooldown = 60

-- High-security car locks (pin tumbler instead of a slim jim) from this level, this often
Config.HighSecurity = { minLevel = 4, chance = 0.4 }

--------------------------------------------------------------------------------
-- NPC calls
--------------------------------------------------------------------------------
Config.Scenarios = {
    { id = 'car', label = 'Car lockout', weight = 35, minLevel = 1,
      lines = { 'Keys are right there on the seat. I can see them!', 'I locked my keys in with the engine running...' } },
    { id = 'house', label = 'House lockout', weight = 30, minLevel = 1,
      lines = { 'The door shut behind me while I took the trash out.', 'Lost my keys somewhere between here and the bar.' } },
    { id = 'key', label = 'Duplicate key', weight = 15, minLevel = 1,
      lines = { 'Can I get a copy of this one? My roommate keeps borrowing mine.' } },
    { id = 'rekey', label = 'Change the locks', weight = 12, minLevel = 2,
      lines = { 'My ex still has a key. I want new locks today.' } },
    { id = 'safe', label = 'Stuck safe', weight = 8, minLevel = 3,
      lines = { 'Grandpa\'s safe. Nobody remembers the combination.' } },
}

Config.Models = { 'asea', 'blista', 'emperor', 'fugitive', 'ingot', 'premier', 'primo', 'stanier', 'tailgater', 'washington', 'dilettante', 'panto' }
Config.Peds = { 'a_m_y_business_01', 'a_f_y_business_01', 'a_m_m_eastsa_01', 'a_f_m_bevhills_01', 'a_m_y_hipster_01', 'a_f_y_tourist_01', 'a_f_y_vinewood_01' }

-- Roads for car lockouts (the car parks on the nearest road side)
Config.Spots = {
    vec3(-1220.0, -1400.0, 4.3), vec3(-700.0, -1100.0, 14.0), vec3(-520.0, -270.0, 35.4), vec3(-60.0, -1100.0, 26.3),
    vec3(250.0, -640.0, 40.0), vec3(330.0, -210.0, 54.0), vec3(1150.0, -460.0, 66.6), vec3(200.0, -1750.0, 29.0),
    vec3(-320.0, -1320.0, 31.3), vec3(-1300.0, -380.0, 36.6), vec3(-900.0, -150.0, 37.6), vec3(100.0, 230.0, 108.0),
}

-- Front doors for house calls: vec4(x, y, z, heading the customer faces). Approximate, check on your map.
Config.Doors = {
    vec4(-14.30, -1441.20, 31.10, 0.0),     -- Forum Dr
    vec4(85.70, -1959.40, 21.10, 320.0),    -- Grove St
    vec4(114.30, -1961.00, 21.30, 30.0),    -- Grove St
    vec4(1060.40, -378.30, 68.20, 40.0),    -- Mirror Park
    vec4(1229.40, -725.40, 60.80, 90.0),    -- Mirror Park
    vec4(-1150.60, -1521.40, 10.60, 35.0),  -- Vespucci
    vec4(-1098.50, -1679.00, 4.40, 300.0),  -- Vespucci
    vec4(-174.20, 502.50, 137.40, 190.0),   -- Vinewood Hills
    vec4(1273.90, -1720.70, 54.80, 20.0),   -- El Burro Heights
    vec4(-817.00, 178.20, 72.20, 110.0),    -- Rockford Hills
}
Config.MinCallDistance = 250.0
Config.MaxCallDistance = 2500.0

-- At the shop: walk-in key copies and stuck safes
Config.Shop = {
    counter = vec4(168.40, -1719.90, 29.29, 50.0), -- where the walk-in customer stands
    bench = vec4(173.10, -1724.80, 29.29, 230.0),  -- where dropped-off safes go
}

--------------------------------------------------------------------------------
-- qs-housing (house lockouts). Swap these out for another housing script.
--------------------------------------------------------------------------------
Config.Housing = {
    resource = 'qs-housing',
    -- client: the house whose zone the player is standing in (or nil)
    currentHouse = function()
        return exports['qs-housing']:getCurrentHouse()
    end,
    -- server: does this player own or rent `house`?
    ownsHouse = function(src, house)
        local list = exports['qs-housing']:GetPlayerHouses(src) or {}
        for _, h in pairs(list) do
            if h == house then return true end
        end
        return false
    end,
    -- client: put the owner inside (no key check)
    enterHouse = function(house)
        exports['qs-housing']:enterHouse(house, false)
    end,
}

-- server: does this citizen own the car with this plate? (qbx player_vehicles)
Config.OwnsVehicle = function(citizenid, plate)
    local row = MySQL.scalar.await('SELECT 1 FROM player_vehicles WHERE citizenid = ? AND plate = ? LIMIT 1', { citizenid, plate })
    return row ~= nil
end

--------------------------------------------------------------------------------
-- NPC locksmith (when a player calls and nobody is on duty)
--------------------------------------------------------------------------------
Config.NpcService = {
    vehicle = 'speedo',
    ped = 's_m_m_lathandy_01',
    spawnDistance = 140.0,
    driveTimeout = 120,
    workTime = 18,
}

Config.Props = { safe = 'prop_ld_int_safe_01' }
Config.Anims = {
    door = { dict = 'mini@safe_cracking', clip = 'idle_base' },
    bench = { dict = 'mini@repair', clip = 'fixing_a_player' },
}
