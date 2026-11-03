Config = {}

Config.Debug = false

Config.Job = {
    id = 'foodtruck',
    label = 'Street Food Vendor',
    description = 'Run a taco truck. Park at a busy spot, open the window and cook orders on the grill. Customers line up, and real players can buy real food from you. Busy spots pay more, but they wear out and other vendors steal your crowd.',
    icon = 'utensils',
    depot = {
        coords = vec4(-1190.50, -891.30, 13.97, 300.0), -- commissary near Vespucci (check on your map)
        ped = 's_m_m_linecook',
        blip = { sprite = 52, color = 47, scale = 0.8, label = 'Food Truck Commissary' },
        radius = 40.0,
    },
    vehicle = {
        model = 'taco',
        label = 'Taco Truck',
        deposit = 800,
        plate = 'TACO',
        spawns = {
            vec4(-1175.40, -884.60, 13.90, 300.0),
            vec4(-1170.20, -880.10, 13.90, 300.0),
        },
    },
    maxEarnPerHour = 22000,
}

--------------------------------------------------------------------------------
-- Menu. `item` is what a real player gets in their inventory (add these items to
-- ox_inventory, or point them at items you already have).
-- grill = what goes on the grill for one serving (nil = nothing to cook)
-- build = the order the ingredients go together (nil = just hand it over)
--------------------------------------------------------------------------------
Config.Menu = {
    { id = 'taco', label = 'Taco', price = 45, item = 'taco', minLevel = 1,
      grill = 'Carne asada', build = { 'Tortilla', 'Carne asada', 'Onion', 'Cilantro', 'Salsa' } },
    { id = 'burrito', label = 'Burrito', price = 75, item = 'burrito', minLevel = 2,
      grill = 'Chicken', build = { 'Tortilla', 'Rice', 'Beans', 'Chicken', 'Cheese', 'Salsa' } },
    { id = 'quesadilla', label = 'Quesadilla', price = 60, item = 'quesadilla', minLevel = 3,
      grill = 'Quesadilla', build = { 'Tortilla', 'Cheese', 'Chicken', 'Sour cream' } },
    { id = 'soda', label = 'Soda', price = 20, item = 'sprunk', minLevel = 1 },
}
-- extra buttons in the assemble minigame, so it isn't just the right answers
Config.Distractors = { 'Lettuce', 'Pickles', 'Jalapeños', 'Guacamole', 'Lime', 'Hot sauce' }

-- server: give a real player the food they bought
Config.GiveItem = function(src, item, count)
    if GetResourceState('ox_inventory') ~= 'started' then return false end
    return exports.ox_inventory:AddItem(src, item, count) ~= false
end

--------------------------------------------------------------------------------
-- Supplies: each serving uses one unit. Restock at the commissary.
--------------------------------------------------------------------------------
Config.Stock = {
    start = 20, -- free supplies when you start a shift
    max = 40,
    cost = 8,   -- per unit when you restock (comes out of your bank)
}

--------------------------------------------------------------------------------
-- Where to sell. Anywhere else counts as a quiet street (demand 0.5).
--------------------------------------------------------------------------------
Config.Spots = {
    { label = 'Vespucci Beach', coords = vec3(-1263.0, -1530.0, 4.3), demand = 1.4 },
    { label = 'Del Perro Pier', coords = vec3(-1628.0, -1015.0, 13.1), demand = 1.5, minLevel = 3 },
    { label = 'Legion Square', coords = vec3(195.0, -935.0, 30.7), demand = 1.3 },
    { label = 'Pillbox Hill', coords = vec3(255.0, -620.0, 41.0), demand = 1.1 },
    { label = 'Vinewood Blvd', coords = vec3(300.0, 180.0, 104.0), demand = 1.2, minLevel = 2 },
    { label = 'Mirror Park', coords = vec3(1100.0, -640.0, 56.8), demand = 1.0 },
    { label = 'Maze Bank Arena', coords = vec3(-260.0, -2030.0, 30.1), demand = 1.3, minLevel = 2 },
    { label = 'LSIA Arrivals', coords = vec3(-1035.0, -2730.0, 20.2), demand = 1.2, minLevel = 4 },
}
Config.SpotRadius = 45.0
Config.QuietDemand = 0.5
Config.Saturation = { perServe = 0.05, floor = 0.4, window = 600 } -- each sale in 10 min lowers a spot's crowd by 5%
Config.Competition = { radius = 120.0, factor = 0.6 }                -- another open truck nearby

--------------------------------------------------------------------------------
-- Customers
--------------------------------------------------------------------------------
Config.Customers = {
    every = 26,        -- seconds between customers at demand 1.0
    queue = 3,         -- most NPCs waiting at once
    patience = 75,     -- seconds before an NPC gives up
    maxItems = 3,      -- per NPC order
    secondsPerItem = 4, -- an order can't be served faster than this
    tipMax = 30,       -- per order, for quality and speed
}
Config.Peds = { 'a_m_y_business_01', 'a_f_y_business_01', 'a_m_m_eastsa_01', 'a_f_m_bevhills_01', 'a_m_y_hipster_01',
    'a_f_y_tourist_01', 'a_m_y_beach_01', 'a_f_y_beach_01', 'a_m_y_stbla_01', 'a_f_m_downtown_01' }

-- Real players
Config.PlayerBonus = 40          -- job bonus per real customer's order (x1.5 player-work boost, once per buyer per 20 min)
Config.PlayerOrderTimeout = 180  -- seconds; the buyer is refunded if it isn't served by then

Config.XP = { order = 4, player = 6 }

-- Where customers stand: right side of the truck (the serving window)
Config.WindowOffset = vec3(2.2, 0.0, 0.0)
