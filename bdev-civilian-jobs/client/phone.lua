--[[
    Registers the "Gigs" app with Quasar Smartphone V3 (qs-smartphone).
    V3 takes { id, label, icon, iframe = { url } ... } and returns ok, errorCode.
    (Smartphone PRO uses a different payload and is not supported here.)
    /gigsapp re-registers and prints the phone's answer in F8.
]]

local resource = GetCurrentResourceName()
local origin = ('https://cfx-nui-%s'):format(resource)
local base = origin .. '/html/app/'
local PHONE = Config.Phone.resource
local registered = false

local function log(msg, ...)
    print(('[civjobs:phone] ' .. msg):format(...))
end

function CJ.phoneReady()
    return Config.Phone.enabled and registered and GetResourceState(PHONE) == 'started'
end

local function payload()
    local a = Config.Phone.app
    return {
        id = a.id,
        label = a.label,
        icon = base .. 'icon.png',
        category = a.category,
        creator = a.creator,
        description = a.description,
        age = a.age,
        appStoreOnly = a.appStoreOnly,
        price = (a.price or 0) > 0 and a.price or nil,
        sizeMb = 2,
        extraDescription = {},
        iframe = { url = base .. 'index.html' },
        custom = {
            enabled = true,
            bridge = { enabled = true, allowedOrigins = { origin } },
        },
    }
end

local function register(verbose)
    if not Config.Phone.enabled then return false end
    if GetResourceState(PHONE) ~= 'started' then
        if verbose then log('%s is not running', PHONE) end
        return false
    end
    local ok, added, err = pcall(function() return exports[PHONE]:addCustomApp(payload()) end)
    if not ok then
        log('addCustomApp errored: %s', tostring(added))
        return false
    end
    if added == false or (added == nil and err) then
        local reason = tostring(err or 'no reason given')
        if reason:lower():find('exist') or reason:lower():find('duplicate') then
            registered = true
            if verbose then log('app already registered') end
            return true
        end
        log('phone refused the app: %s', reason)
        return false
    end
    registered = true
    if verbose or Config.Debug then log('app registered with %s', PHONE) end
    return true
end

local function registerWhenReady()
    if not Config.Phone.enabled then return end
    CreateThread(function()
        local waited = 0
        while GetResourceState(PHONE) ~= 'started' and waited < 60000 do
            Wait(500)
            waited = waited + 500
        end
        if GetResourceState(PHONE) ~= 'started' then return end
        Wait(1000)
        for attempt = 1, 5 do
            if register(attempt == 1 and Config.Debug) then return end
            Wait(3000)
        end
    end)
end

registerWhenReady()

AddEventHandler('onClientResourceStart', function(res)
    if res == PHONE then
        registered = false
        registerWhenReady()
    end
end)

AddEventHandler('onClientResourceStop', function(res)
    if res == PHONE then registered = false end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    if not registered then registerWhenReady() end
end)

AddEventHandler('onResourceStop', function(res)
    if res == resource and GetResourceState(PHONE) == 'started' then
        pcall(function() exports[PHONE]:removeCustomApp(Config.Phone.app.id) end)
    end
end)

if Config.Phone.command then
    RegisterCommand(Config.Phone.command, function()
        log('phone resource: %s (%s)', PHONE, GetResourceState(PHONE))
        if register(true) then
            CJ.notify('Gigs app registered with the phone.', 'success')
        else
            CJ.notify('The phone refused the Gigs app. See the F8 console.', 'error')
        end
    end, false)
end
