Config = {}

Config.Debug = false

Config.Job = {
    id = 'bus',
    label = 'Bus Driver',
    description = 'Drive timetabled routes. Stop right at the bus stop, take fares and make change, spot fake passes and keep the ride smooth. Real players can ride your bus.',
    icon = 'bus',
    depot = {
        coords = vec4(462.22, -641.15, 28.45, 175.0), -- LS Transit depot (check on your map)
        ped = 's_m_m_gentransport',
        blip = { sprite = 513, color = 38, scale = 0.8, label = 'Bus Depot' },
        radius = 45.0,
    },
    vehicle = {
        model = 'bus',
        label = 'City Bus',
        deposit = 1000,
        plate = 'LSTR',
        spawns = {
            vec4(462.70, -618.40, 28.50, 215.0),
            vec4(470.10, -612.30, 28.50, 215.0),
        },
    },
    maxEarnPerHour = 22000,
}

--------------------------------------------------------------------------------
-- Routes. Stops are approximate: drive them and fix with /civjobs pos.
--------------------------------------------------------------------------------
Config.Routes = {
    {
        id = 'city', label = 'City Loop', minLevel = 1, zone = 'City', bonus = 600,
        stops = {
            { label = 'Mission Row', coords = vec3(413.0, -955.0, 29.3) },
            { label = 'Legion Square', coords = vec3(195.0, -1005.0, 29.3) },
            { label = 'Pillbox Hill', coords = vec3(309.95, -760.52, 29.31) },
            { label = 'Alta Street', coords = vec3(-250.14, -886.78, 30.63) },
            { label = 'Little Seoul', coords = vec3(-712.83, -824.56, 23.54) },
            { label = 'Vespucci Blvd', coords = vec3(-692.63, -670.44, 30.86) },
            { label = 'Transit Depot', coords = vec3(452.0, -590.0, 28.5) },
        },
    },
    {
        id = 'airport', label = 'Airport Express', minLevel = 2, zone = 'Airport', bonus = 800,
        stops = {
            { label = 'Strawberry', coords = vec3(-110.31, -1686.29, 29.31) },
            { label = 'LSIA Terminal', coords = vec3(-1037.77, -2737.83, 20.17) },
            { label = 'Vespucci Beach', coords = vec3(-1220.0, -1400.0, 4.3) },
            { label = 'Del Perro', coords = vec3(-1440.0, -660.0, 28.6) },
            { label = 'Transit Depot', coords = vec3(452.0, -590.0, 28.5) },
        },
    },
    {
        id = 'vinewood', label = 'Vinewood Tour', minLevel = 3, zone = 'Vinewood', bonus = 900,
        stops = {
            { label = 'Burton', coords = vec3(-505.0, -270.0, 35.4) },
            { label = 'Vinewood Blvd', coords = vec3(300.0, 170.0, 104.0) },
            { label = 'Mirror Park', coords = vec3(1150.0, -460.0, 66.6) },
            { label = 'La Mesa', coords = vec3(810.0, -1080.0, 28.0) },
            { label = 'Transit Depot', coords = vec3(452.0, -590.0, 28.5) },
        },
    },
    {
        id = 'paleto', label = 'Paleto Run', minLevel = 4, zone = 'County', bonus = 1800,
        stops = {
            { label = 'Sandy Shores', coords = vec3(1950.0, 3740.0, 32.2) },
            { label = 'Grapeseed', coords = vec3(1700.0, 4800.0, 41.9) },
            { label = 'Paleto Bay', coords = vec3(-160.0, 6380.0, 31.4) },
            { label = 'Great Ocean Hwy', coords = vec3(-2200.0, 4300.0, 49.0) },
            { label = 'Transit Depot', coords = vec3(452.0, -590.0, 28.5) },
        },
    },
}

Config.StopRadius = 14.0  -- how close the bus must be to count as "at the stop"
Config.AvgSpeed = 13.0    -- m/s, used to build the timetable
Config.MaxSpeed = 45.0    -- m/s, anything faster between stops is rejected (teleporting)
Config.Dwell = 25         -- seconds planned at each stop
Config.LateGrace = 45     -- seconds late before it counts
Config.EarlyGrace = 20    -- leaving more than this early counts against you
Config.SpeedLimit = 27.0  -- m/s (~60 mph) before passengers complain
Config.Capacity = 8       -- NPC passengers on board at once

Config.Passengers = { min = 0, max = 3, cashChance = 0.6 }

Config.Pay = {
    stop = 110,      -- per stop (scaled by how close you stopped)
    fare = 35,       -- cash fare collected with correct change
    pass = 25,       -- valid pass accepted
    caught = 40,     -- fake pass caught
    playerFare = 25, -- what a real player pays to ride
    playerBonus = 200, -- job bonus per real rider (x1.5 player-work boost, once per rider per 20 min)
}
Config.XP = { stop = 4, route = 25, passenger = 1 }

-- Player riders
Config.WaitCommand = 'waitbus' -- also an ox_target option at every stop
Config.BellKey = 'G'           -- passengers ring the stop bell
