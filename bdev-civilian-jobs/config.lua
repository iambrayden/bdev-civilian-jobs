Config = {}

Config.Debug = false             -- prints extra logs and draws ox_target zones
Config.Currency = '$'
Config.AdminGroup = 'group.admin' -- who can use /civjobs

--------------------------------------------------------------------------------
-- Turning jobs on / off
--
-- Every job is its own addon resource (bdev-cj-roadside, ...). A job that is not
-- listed here uses Config.DefaultEnabled.
--
-- Admins can also flip jobs live in game with /civjobs (or `civjobs enable|disable
-- <id>` in the server console). That choice is saved and wins over this table
-- until you run `civjobs reset`.
--------------------------------------------------------------------------------
Config.DefaultEnabled = true
Config.Jobs = {
    roadside = true,
    bus = true,
    locksmith = true,
    repo = true,
}

--------------------------------------------------------------------------------
-- Job Center: an NPC that lists every job that is hiring and sets GPS to it.
--------------------------------------------------------------------------------
Config.JobCenter = {
    enabled = true,
    ped = 'a_f_y_business_02',
    coords = vec4(-268.53, -957.85, 31.22, 205.0), -- player position; the ped is placed on the ground
    blip = { sprite = 407, color = 27, scale = 0.8, label = 'Job Center' },
    command = 'jobs',                               -- /jobs opens the list anywhere (false = off)
}

--------------------------------------------------------------------------------
-- Levels: XP is tracked per player, per job.
--------------------------------------------------------------------------------
Config.Levels = {
    -- total XP needed to reach level 1, 2, 3 ...
    xp = { 0, 100, 250, 450, 700, 1000, 1400, 1900, 2500, 3200 },
    payBonus = 0.03,     -- +3% job pay per level above 1 (level 10 = +27%)
    minigameEase = 0.04, -- minigames get 4% easier per level above 1
}

--------------------------------------------------------------------------------
-- Pay & anti-exploit
--------------------------------------------------------------------------------
Config.Limits = {
    maxEarnPerHour = 20000, -- per player, per job (a job can set its own maxEarnPerHour)
    minRewardGap = 1.0,     -- seconds between two paid actions
    startCooldown = 20,     -- seconds between starting shifts (stops vehicle spam)
    depotDistance = 6.0,    -- how close to the depot NPC you must be to start / end a shift
}

Config.Payment = {
    account = 'bank',                    -- where job pay goes
    chargeAccounts = { 'bank', 'cash' }, -- deposits and service requests are taken from the first one with enough money
}

Config.RefundOnDisconnect = true -- refund the vehicle deposit if a player drops mid-shift
Config.DamageRefund = true       -- deposit refund scales with the vehicle's condition when returned

--------------------------------------------------------------------------------
-- Service requests (jobs that real players can call, e.g. roadside assistance)
--------------------------------------------------------------------------------
Config.Requests = {
    expireAfter = 900,         -- seconds an unanswered request stays open before it is refunded
    npcAfter = 120,            -- workers are on duty but nobody accepted: send an NPC after this long
    pairBonusCooldown = 1800,  -- the job's bonus is only paid once per requester + worker pair in this window
    command = 'service',       -- /service: request a service without a phone
    queueCommand = 'jobqueue', -- /jobqueue: on-duty workers see open requests without a phone
}

--------------------------------------------------------------------------------
-- Quasar Smartphone V3 app ("Gigs")
--------------------------------------------------------------------------------
Config.Phone = {
    enabled = true,
    resource = 'qs-smartphone',
    command = 'gigsapp', -- re-registers the app and prints the phone's answer in F8
    app = {
        id = 'bdev_gigs',
        label = 'Gigs',
        category = 'Utilities',
        creator = 'bdev',
        description = 'Find work, track your shift and request roadside help, locksmiths and more.',
        age = '16+',
        appStoreOnly = false, -- false = on every home screen
        price = 0,
    },
}

--------------------------------------------------------------------------------
-- Integrations (adapt if you use other key / fuel resources)
--------------------------------------------------------------------------------
Config.GiveKeys = function(source, vehicle, plate)
    if GetResourceState('qbx_vehiclekeys') == 'started' then
        pcall(function() exports.qbx_vehiclekeys:GiveKeys(source, vehicle, true) end)
    end
end

Config.SetFuel = function(vehicle, level)
    Entity(vehicle).state.fuel = level or 100.0 -- ox_fuel / qbx statebag fuel
end
