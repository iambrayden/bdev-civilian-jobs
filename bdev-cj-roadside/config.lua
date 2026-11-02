Config = {}

Config.Debug = false

--------------------------------------------------------------------------------
-- Job definition (sent to bdev-civilian-jobs). Turn the job on/off there with /civjobs.
--------------------------------------------------------------------------------
Config.Job = {
    id = 'roadside',
    label = 'Roadside Assistance',
    description = 'Drive a service truck out to stranded drivers. Change flats, jump batteries, refuel, cool overheating engines and winch rolled cars back onto their wheels. Real players can call you; NPC calls fill the gaps.',
    icon = 'wrench',
    depot = {
        coords = vec4(471.39, -1311.03, 29.21, 114.5), -- Hayes Autos, Strawberry
        ped = 's_m_m_autoshop_01',
        blip = { sprite = 446, color = 47, scale = 0.8, label = 'Roadside Assistance' },
        radius = 40.0, -- the truck counts as returned inside this radius
    },
    vehicle = {
        model = 'utillitruck3',
        label = 'Service Truck',
        deposit = 600,
        plate = 'AID',
        spawns = {
            vec4(489.65, -1331.82, 29.33, 306.5),
            vec4(494.13, -1336.56, 29.33, 306.5),
            vec4(484.90, -1327.10, 29.33, 306.5),
        },
    },
    maxEarnPerHour = 22000,

    -- Players can call a mechanic from the Gigs app or /service
    requests = {
        label = 'Roadside assistance',
        description = 'Flat tire, engine trouble, empty tank, body damage or rolled over? A mechanic comes to you.',
        price = 400,    -- paid by the caller to the player mechanic
        npcPrice = 650, -- nobody on duty: an NPC mechanic comes instead (set nil to disable)
        bonus = 150,    -- extra the job pays the mechanic (once per caller every 30 min)
        needsVehicle = true,
    },
}

--------------------------------------------------------------------------------
-- Pay
--------------------------------------------------------------------------------
Config.Pay = {
    -- NPC calls: paid per fixed problem ...
    issue = { tire = 220, battery = 200, fuel = 150, coolant = 230, engine = 300, flipped = 280, body = 180, inspect = 60 },
    -- ... plus a tip for quality (minigame scores) and getting there fast
    tipMax = 250,
    responseTarget = 240, -- seconds from call to arrival for the full speed part of the tip
    -- Player calls: the caller's money + the job bonus above + this per problem
    playerIssue = 60,
}

Config.XP = { issue = 6, call = 10 }

Config.MinTaskSeconds = 6     -- the server rejects repairs faster than this (no instant fixes)
Config.NextCallDelay = { 8, 20 } -- seconds between finishing a call and the next NPC call
Config.SkipCooldown = 60      -- seconds between skipping NPC calls

-- What counts as a problem when a player's car is diagnosed
Config.Thresholds = {
    engine = 650.0, -- engine health below this = engine repair
    body = 750.0,   -- body health below this = body work
    fuel = 15.0,    -- fuel below this = refuel
}

-- How far a roadside repair goes. There is no mechanic job on the server, so
-- by default roadside fully fixes what it touches.
Config.Repair = {
    engine = 1000.0,
    fuel = 40.0, -- jerry can fills to this level
}

--------------------------------------------------------------------------------
-- NPC mechanic: comes out when a player requests help and nobody is on duty.
--------------------------------------------------------------------------------
Config.NpcService = {
    truck = 'utillitruck3',
    ped = 's_m_m_autoshop_01',
    spawnDistance = 140.0, -- how far away the NPC truck appears
    driveTimeout = 120,    -- seconds before a stuck NPC truck is moved closer
    workTime = 22,         -- seconds the NPC spends on the car
    fullRepair = true,     -- true: the NPC fixes everything; false: only tires, engine, fuel and flips
}

--------------------------------------------------------------------------------
-- NPC calls (solo work)
--------------------------------------------------------------------------------
Config.Scenarios = {
    {
        id = 'flat', label = 'Flat tire', issues = { 'tire' }, weight = 30, minLevel = 1,
        lines = { 'Blew a tire on a pothole. I don\'t even know where the jack is.', 'Flat tire, and I\'m already late. Please tell me you\'re quick.' },
    },
    {
        id = 'battery', label = 'Dead battery', issues = { 'battery' }, weight = 25, minLevel = 1,
        lines = { 'It just clicks when I turn the key.', 'Left the lights on all night. Rookie move.' },
    },
    {
        id = 'fuel', label = 'Out of fuel', issues = { 'fuel' }, weight = 20, minLevel = 1,
        lines = { 'The gauge said a quarter tank. The gauge lied.', 'I was SURE I could make it to the next station.' },
    },
    {
        id = 'overheat', label = 'Overheating', issues = { 'coolant' }, weight = 15, minLevel = 2,
        lines = { 'Steam started pouring out of the hood!', 'The temperature light came on and then... this.' },
    },
    {
        id = 'rollover', label = 'Rolled over', issues = { 'flipped' }, weight = 10, minLevel = 3,
        lines = { 'Took the corner a little hot. I\'m fine, the car isn\'t.', 'Don\'t ask. Just flip it back please.' },
    },
    {
        id = 'bad_day', label = 'Flat tire and a dead battery', issues = { 'tire', 'battery' }, weight = 8, minLevel = 4,
        lines = { 'Flat tire AND the battery died while I waited. Worst day ever.' },
    },
    {
        id = 'stranded', label = 'Out of fuel and overheating', issues = { 'fuel', 'coolant' }, weight = 6, minLevel = 5,
        lines = { 'Ran it dry and now it\'s steaming. I think I made it worse.' },
    },
}

Config.Models = {
    'asea', 'blista', 'emperor', 'fugitive', 'glendale', 'ingot', 'intruder', 'premier', 'primo',
    'regina', 'stanier', 'tailgater', 'washington', 'asterope', 'dilettante', 'issi2', 'panto', 'rhapsody',
}

Config.Peds = {
    'a_m_y_business_01', 'a_f_y_business_01', 'a_m_m_eastsa_01', 'a_f_m_bevhills_01',
    'a_m_y_hipster_01', 'a_f_y_tourist_01', 'a_m_m_farmer_01', 'a_f_y_vinewood_01',
}

-- Rough spots around the city. The broken-down car is placed on the nearest
-- road side, so these don't need to be exact.
Config.Spots = {
    vec3(-1037.0, -2730.0, 20.2), vec3(-1220.0, -1400.0, 4.3), vec3(-1500.0, -900.0, 10.0),
    vec3(-700.0, -1100.0, 14.0), vec3(-520.0, -270.0, 35.4), vec3(-60.0, -1100.0, 26.3),
    vec3(250.0, -640.0, 40.0), vec3(330.0, -210.0, 54.0), vec3(870.0, -170.0, 77.0),
    vec3(1150.0, -460.0, 66.6), vec3(1210.0, -1400.0, 35.0), vec3(840.0, -2000.0, 29.3),
    vec3(200.0, -1750.0, 29.0), vec3(-170.0, -1650.0, 33.0), vec3(-320.0, -1320.0, 31.3),
    vec3(-1300.0, -380.0, 36.6), vec3(-1650.0, -500.0, 35.0), vec3(-900.0, -150.0, 37.6),
    vec3(100.0, 230.0, 108.0), vec3(600.0, 100.0, 92.0), vec3(1000.0, -2300.0, 30.5),
    vec3(-400.0, -1800.0, 21.0), vec3(-1050.0, -1600.0, 4.4), vec3(400.0, -1600.0, 29.3),
}
Config.MinCallDistance = 300.0  -- NPC calls are at least this far from you ...
Config.MaxCallDistance = 2500.0 -- ... and at most this far (when possible)

--------------------------------------------------------------------------------
-- Props & animations
--------------------------------------------------------------------------------
Config.Props = {
    wheel = 'prop_wheel_01',
    jack = 'prop_carjack',
    jerrycan = 'w_am_jerrycan',
    coolant = 'prop_oilcan_01a',
}

Config.Anims = {
    kneel = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' },
    hood = { dict = 'mini@repair', clip = 'fixing_a_player' },
    pour = { dict = 'weapon@w_sp_jerrycan', clip = 'fire' },
}
