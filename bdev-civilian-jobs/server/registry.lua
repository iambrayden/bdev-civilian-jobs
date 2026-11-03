-- Job addons register here. Admins turn them on / off with /civjobs.

CJ.Jobs = {}

local overrides = json.decode(GetResourceKvpString('overrides') or '{}') or {}

local function saveOverrides()
    SetResourceKvp('overrides', json.encode(overrides))
end

local function configDefault(id)
    local v = Config.Jobs[id]
    if v == nil then return Config.DefaultEnabled end
    return v == true
end

function CJ.isEnabled(id)
    if not CJ.Jobs[id] then return false end
    if overrides[id] ~= nil then return overrides[id] end
    return configDefault(id)
end

function CJ.hasOverride(id)
    return overrides[id] ~= nil
end

--- What clients get to see about each job (GlobalState.civjobs).
function CJ.publicJob(job)
    local r = job.requests
    return {
        id = job.id,
        label = job.label,
        description = job.description,
        icon = job.icon,
        enabled = CJ.isEnabled(job.id),
        depot = { coords = job.depot.coords, ped = job.depot.ped, blip = job.depot.blip },
        vehicle = job.vehicle and { label = job.vehicle.label, deposit = job.vehicle.deposit } or nil,
        resource = job.resource,
        requests = r and CJ.publicRequestInfo(r) or nil,
    }
end

function CJ.publicRequestInfo(r)
    local types
    if r.types then
        types = {}
        for _, t in ipairs(r.types) do
            types[#types + 1] = { id = t.id, label = t.label, description = t.description, price = t.price, npcPrice = t.npcPrice, needsVehicle = t.needsVehicle }
        end
    end
    return {
        label = r.label,
        description = r.description,
        price = r.price,
        npcPrice = r.npcPrice,
        needsVehicle = r.needsVehicle,
        context = r.context,
        types = types,
    }
end

function CJ.publish()
    local out = {}
    for id, job in pairs(CJ.Jobs) do out[id] = CJ.publicJob(job) end
    GlobalState.civjobs = out
end

local function validate(def)
    if type(def) ~= 'table' then return 'definition must be a table' end
    if type(def.id) ~= 'string' or not def.id:match('^[%w_%-]+$') then return 'id must use letters, numbers, _ or -' end
    if type(def.label) ~= 'string' then return 'label is required' end
    local d = def.depot
    if type(d) ~= 'table' or type(d.coords) ~= 'vector4' then return 'depot.coords must be a vec4' end
    local v = def.vehicle
    if v ~= nil then
        if type(v) ~= 'table' or type(v.model) ~= 'string' then return 'vehicle.model is required' end
        if type(v.spawns) ~= 'table' or #v.spawns == 0 then return 'vehicle.spawns needs at least one vec4' end
        for _, s in ipairs(v.spawns) do
            if type(s) ~= 'vector4' then return 'vehicle.spawns must all be vec4' end
        end
    end
    local r = def.requests
    if r ~= nil then
        if type(r) ~= 'table' or type(r.price) ~= 'number' or r.price < 0 then return 'requests.price must be a number' end
        if r.npcPrice ~= nil and type(r.npcPrice) ~= 'number' then return 'requests.npcPrice must be a number' end
        if r.types ~= nil then
            if type(r.types) ~= 'table' or #r.types == 0 then return 'requests.types must be a list' end
            for _, t in ipairs(r.types) do
                if type(t.id) ~= 'string' or type(t.label) ~= 'string' or type(t.price) ~= 'number' then
                    return 'each request type needs id, label and price'
                end
            end
        end
    end
    return nil
end

function CJ.registerJob(def, resource)
    local err = validate(def)
    if err then
        print(('^1[civjobs] %s tried to register an invalid job: %s^0'):format(resource, err))
        return false, err
    end
    local existing = CJ.Jobs[def.id]
    if existing and existing.resource ~= resource and GetResourceState(existing.resource) == 'started' then
        print(('^1[civjobs] %s tried to register "%s", but %s already uses that id^0'):format(resource, def.id, existing.resource))
        return false, 'id already registered'
    end

    def.resource = resource
    def.depot.radius = def.depot.radius or 40.0
    if def.vehicle then
        def.vehicle.deposit = math.floor(def.vehicle.deposit or 0)
        def.vehicle.label = def.vehicle.label or def.vehicle.model
    end
    if def.requests then
        def.requests.label = def.requests.label or def.label
        def.requests.bonus = def.requests.bonus or 0
        def.requests.needsVehicle = def.requests.needsVehicle == true
        -- the cheapest type is what menus show as "from" price
        if def.requests.types then
            local low, lowNpc
            for _, t in ipairs(def.requests.types) do
                t.needsVehicle = t.needsVehicle == true
                if not low or t.price < low then low = t.price end
                if t.npcPrice and (not lowNpc or t.npcPrice < lowNpc) then lowNpc = t.npcPrice end
            end
            def.requests.price = low
            def.requests.npcPrice = lowNpc
        end
    end

    CJ.Jobs[def.id] = def
    print(('[civjobs] registered job "%s" from %s (%s)'):format(def.id, resource,
        CJ.isEnabled(def.id) and 'enabled' or 'disabled'))
    CJ.publish()
    return true
end

--- state: true / false, or nil to go back to config.lua
function CJ.setEnabled(id, state)
    overrides[id] = state
    saveOverrides()
    if not CJ.isEnabled(id) then
        CJ.endJobSessions(id, 'disabled')
        CJ.cancelJobRequests(id, 'That service is no longer available.')
    end
    CJ.publish()
end

function CJ.resetOverrides()
    overrides = {}
    saveOverrides()
    for id in pairs(CJ.Jobs) do
        if not CJ.isEnabled(id) then
            CJ.endJobSessions(id, 'disabled')
            CJ.cancelJobRequests(id, 'That service is no longer available.')
        end
    end
    CJ.publish()
end

exports('RegisterJob', function(def)
    return CJ.registerJob(def, GetInvokingResource() or CJ.Resource)
end)

exports('IsEnabled', CJ.isEnabled)

-- An addon stopped: its jobs go away and anyone working them is sent home.
AddEventHandler('onResourceStop', function(res)
    if res == CJ.Resource then return end
    local changed = false
    for id, job in pairs(CJ.Jobs) do
        if job.resource == res then
            CJ.endJobSessions(id, 'unavailable')
            CJ.cancelJobRequests(id, 'That service is no longer available.')
            CJ.Jobs[id] = nil
            changed = true
        end
    end
    if changed then CJ.publish() end
end)

GlobalState.civjobs = {}

-- Tell addons that are already running to (re)register, e.g. after `restart bdev-civilian-jobs`.
CreateThread(function()
    Wait(0)
    TriggerEvent('bdev-civilian-jobs:ready')
end)
