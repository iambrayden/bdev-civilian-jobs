Config = {}

Config.Debug = false

Config.Job = {
    id = 'repo',
    label = 'Repo Agent',
    description = 'Track down cars whose owners stopped paying. Work a search area, question witnesses, scan plates, then slim jim and hotwire the car or strap it to your flatbed. Some owners will argue. NPC cases only.',
    icon = 'file-contract',
    depot = {
        coords = vec4(-23.50, -1094.50, 27.27, 340.0), -- next to Premium Deluxe Motorsport (check on your map)
        ped = 's_m_m_ciasec_01',
        blip = { sprite = 67, color = 1, scale = 0.8, label = 'Repo Office' },
        radius = 45.0,
    },
    vehicle = {
        model = 'flatbed',
        label = 'Repo Flatbed',
        deposit = 1000,
        plate = 'REPO',
        spawns = {
            vec4(-14.80, -1081.40, 26.67, 160.0),
            vec4(-9.90, -1083.20, 26.67, 160.0),
        },
    },
    maxEarnPerHour = 24000,
}

Config.DropOff = { coords = vec3(-30.50, -1080.50, 26.63), radius = 14.0, label = 'Dealership lot' }

Config.Pay = {
    base = 900,      -- recovered car in perfect condition
    perKm = 120,     -- + per km from where it was found to the lot
    settle = 450,    -- the owner pays up on the spot instead
    found = 120,     -- bonus for finding it with the plate reader
}
Config.XP = { found = 8, recovered = 25, settled = 12 }

Config.NextCaseDelay = { 8, 18 }
Config.SkipCooldown = 90
Config.MinCaseSeconds = 90 -- a case can't be delivered faster than this

-- Search areas: the car is somewhere near one of these (on a road)
Config.Areas = {
    vec3(-1220.0, -1400.0, 4.3), vec3(-700.0, -1100.0, 14.0), vec3(-520.0, -270.0, 35.4), vec3(250.0, -640.0, 40.0),
    vec3(1150.0, -460.0, 66.6), vec3(1210.0, -1400.0, 35.0), vec3(200.0, -1750.0, 29.0), vec3(-1300.0, -380.0, 36.6),
    vec3(-900.0, -150.0, 37.6), vec3(100.0, 230.0, 108.0), vec3(-1650.0, -500.0, 35.0), vec3(840.0, -2000.0, 29.3),
}
Config.AreaRadius = 220.0     -- size of the first search circle
Config.ClueRadius = 70.0      -- size after a good tip
Config.Witnesses = 3
Config.TruthChance = 0.65     -- + 3% per level

Config.Models = { 'sultan', 'buffalo', 'oracle', 'felon', 'schafter2', 'jackal', 'baller', 'dubsta', 'tailgater', 'zion', 'fugitive', 'washington' }
Config.Owners = { 'Darnell Hayes', 'Trish Kowalski', 'Marco Silva', 'Jenny Park', 'Leon Brooks', 'Rhonda Price', 'Victor Mendes', 'Kayla Novak' }
Config.Colors = { 'black', 'white', 'silver', 'red', 'blue', 'dark green', 'gold' }
Config.ColorIds = { black = 0, white = 111, silver = 4, red = 27, blue = 64, ['dark green'] = 49, gold = 37 }
Config.Peds = { 'a_m_y_business_01', 'a_f_y_business_01', 'a_m_m_eastsa_01', 'a_m_y_hipster_01', 'a_f_y_tourist_01', 'a_m_m_farmer_01', 'a_m_y_stbla_01' }

-- Owner shows up while you work
Config.Confront = {
    chance = 0.35,
    talkChance = 0.55, -- "show the repo order" works this often (+4% per level)
    attackChance = 0.5, -- when talking fails or you ignore them
}

Config.ScanKey = 'J'      -- plate reader (while in your flatbed)
Config.ScanRange = 30.0
Config.Attach = vec3(0.0, -2.35, 1.15) -- where a car sits on the flatbed bed

Config.Hotwire = {
    clamps = {
        { id = 'red', label = 'Red (battery)', color = '#e74c3c' },
        { id = 'brown', label = 'Brown (starter)', color = '#8e5a2b' },
    },
    terminals = {
        { id = 'ign', label = 'Yellow (ignition)' },
        { id = 'bat', label = 'Red (battery)' },
        { id = 'acc', label = 'Blue (accessory)' },
    },
    order = { { 'red', 'ign' }, { 'red', 'acc' }, { 'brown', 'bat' } },
}
