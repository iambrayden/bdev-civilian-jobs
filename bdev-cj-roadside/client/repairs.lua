-- Repair procedures. Each one chains minigames from the base kit and returns
--   true, quality (0-1)      the repair is done
--   false, 'message'|nil     not done (message shown to the player)

Roadside = {}
Roadside.WHEEL_BONES = { [0] = 'wheel_lf', [1] = 'wheel_rf', [4] = 'wheel_lr', [5] = 'wheel_rr' }

local MG = CivJobs.minigame
local spareAt = {} -- issue key -> true once a spare wheel has been carried over

local function anim(a)
    CivJobs.playAnim(a.dict, a.clip, -1, 1)
end

local function stopAnim()
    ClearPedTasks(cache.ped)
end

local function face(ent)
    TaskTurnPedToFaceEntity(cache.ped, ent, 700)
    Wait(700)
end

local function shock()
    ApplyDamageToPed(cache.ped, 5, false)
    SetPedToRagdoll(cache.ped, 1800, 1800, 0, false, false, false)
    CivJobs.notify('ZAP! Wrong order, and the cables sparked.', 'error')
end

local function scald()
    ApplyDamageToPed(cache.ped, 8, false)
    SetPedToRagdoll(cache.ped, 1200, 1200, 0, false, false, false)
    CivJobs.notify('Ouch! Boiling coolant sprayed out. Open it slower next time.', 'error')
end

--- Runs minigames in order. Stops at the first one that isn't passed.
local function steps(list)
    local total, n = 0, 0
    for _, fn in ipairs(list) do
        local res = fn()
        if not res or not res.success then
            return false, res and res.cancelled and nil or 'Not quite. Try again.', res
        end
        total = total + (res.quality or 0)
        n = n + 1
    end
    return true, n > 0 and total / n or 1.0
end

local function localProp(model, coords)
    local ok, hash = pcall(lib.requestModel, model, 5000)
    if not ok or not hash then return nil end
    local obj = CreateObject(hash, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    return obj
end

local function truckNear(veh, dist)
    local truck = CivJobs.vehicle()
    return truck ~= nil and #(GetEntityCoords(truck) - GetEntityCoords(veh)) <= dist
end

--------------------------------------------------------------------------------
-- Player cars: plug in the scanner, then report what the server can't see
--------------------------------------------------------------------------------
function Roadside.diagnose(veh)
    face(veh)
    anim(Config.Anims.hood)
    local res = MG('wiring', { mode = 'match', title = 'Plug in the diagnostic scanner', count = 3, difficulty = 0.3 })
    stopAnim()
    if not res.success then return false, not res.cancelled and 'The scanner didn\'t connect. Try again.' or nil end
    local tires = {}
    for w in pairs(Roadside.WHEEL_BONES) do
        if IsVehicleTyreBurst(veh, w, false) then tires[#tires + 1] = w end
    end
    return true, { tires = tires, fuel = GetVehicleFuelLevel(veh) }
end

--------------------------------------------------------------------------------
-- Flat tire: bring the spare, jack it up, star-pattern the nuts, torque the new wheel
--------------------------------------------------------------------------------
function Roadside.tire(veh, issue)
    if not spareAt[issue.key] then
        if not CivJobs.isCarrying(Config.Props.wheel) then
            return false, 'Grab a spare wheel from your truck first.'
        end
        CivJobs.dropCarry()
        spareAt[issue.key] = true
    end
    face(veh)
    local bone = GetEntityBoneIndexByName(veh, Roadside.WHEEL_BONES[issue.wheel] or 'wheel_lf')
    local wpos = bone ~= -1 and GetWorldPositionOfEntityBone(veh, bone) or GetEntityCoords(veh)
    local jack = localProp(Config.Props.jack, wpos)
    anim(Config.Anims.kneel)
    local ok, q = steps({
        function() return MG('pump', { title = 'Raise the jack', hits = 4, difficulty = 0.4 }) end,
        function() return MG('nuts', { title = 'Loosen the lug nuts', action = 'Loosen', count = 5 }) end,
        function() return MG('torque', { title = 'Torque the new wheel on', count = 5 }) end,
    })
    stopAnim()
    if jack and DoesEntityExist(jack) then DeleteEntity(jack) end
    if ok then spareAt[issue.key] = nil end
    return ok, q
end

--------------------------------------------------------------------------------
-- Dead battery: truck alongside, jumper cables in the safe order, crank it
--------------------------------------------------------------------------------
local JUMP = {
    clamps = {
        { id = 'red', label = 'Red clamp', color = '#e74c3c' },
        { id = 'black', label = 'Black clamp', color = '#2d2d2d' },
    },
    terminals = {
        { id = 'good_neg', label = 'Truck battery  −' },
        { id = 'ground', label = 'Bare metal on the engine' },
        { id = 'dead_pos', label = 'Dead battery  +' },
        { id = 'good_pos', label = 'Truck battery  +' },
    },
    order = { { 'red', 'dead_pos' }, { 'red', 'good_pos' }, { 'black', 'good_neg' }, { 'black', 'ground' } },
}

function Roadside.battery(veh)
    if not truckNear(veh, 12.0) then return false, 'Park your truck right next to the car to jump it.' end
    SetVehicleDoorOpen(veh, 4, false, false)
    face(veh)
    anim(Config.Anims.hood)
    local res = MG('wiring', {
        mode = 'sequence',
        title = 'Jump start',
        hint = 'Connect the jumper cables in the safe order. Ground goes on last, away from the battery.',
        clamps = JUMP.clamps, terminals = JUMP.terminals, order = JUMP.order,
        misses = 2,
    })
    if res.shock then shock() end
    if not res.success then
        stopAnim()
        return false, not res.cancelled and 'The jump didn\'t work. Try again.' or nil
    end
    CivJobs.notify('Cables on. Crank it over!', 'inform')
    local cranked = lib.skillCheck({ 'easy', 'medium' }, { 'e' })
    stopAnim()
    SetVehicleDoorShut(veh, 4, false)
    if not cranked then return false, 'It didn\'t catch. Try cranking again.' end
    return true, res.quality
end

--------------------------------------------------------------------------------
-- Engine damage: reconnect the harness, bolt the mounts down
--------------------------------------------------------------------------------
function Roadside.engine(veh)
    SetVehicleDoorOpen(veh, 4, false, false)
    face(veh)
    anim(Config.Anims.hood)
    local ok, q = steps({
        function() return MG('wiring', { mode = 'match', title = 'Reconnect the wiring harness', count = 5 }) end,
        function() return MG('torque', { title = 'Bolt the engine mounts down', count = 3 }) end,
    })
    stopAnim()
    SetVehicleDoorShut(veh, 4, false)
    return ok, q
end

--------------------------------------------------------------------------------
-- Out of fuel: jerry can from the truck, pour without spilling
--------------------------------------------------------------------------------
function Roadside.fuel(veh)
    if not CivJobs.isCarrying(Config.Props.jerrycan) then return false, 'Grab a jerry can from your truck first.' end
    face(veh)
    anim(Config.Anims.pour)
    local res = MG('pour', { title = 'Refuel', label = 'Tank', color = '#f5a524', hint = 'Hold SPACE to pour, stop in the green band, ENTER when done.' })
    stopAnim()
    if not res.success then return false, not res.cancelled and 'Try again.' or nil end
    CivJobs.dropCarry()
    return true, res.quality
end

--------------------------------------------------------------------------------
-- Overheating: crack the radiator cap carefully, top up coolant
--------------------------------------------------------------------------------
function Roadside.coolant(veh)
    if not CivJobs.isCarrying(Config.Props.coolant) then return false, 'Grab coolant from your truck first.' end
    SetVehicleDoorOpen(veh, 4, false, false)
    face(veh)
    anim(Config.Anims.hood)
    CivJobs.notify('Ease the radiator cap open. It\'s under pressure.', 'inform')
    if not lib.skillCheck({ 'medium', 'medium' }, { 'e' }) then
        stopAnim()
        scald()
        return false
    end
    local res = MG('pour', { title = 'Top up the coolant', label = 'Coolant', color = '#2ecc71' })
    stopAnim()
    SetVehicleDoorShut(veh, 4, false)
    if not res.success then return false, not res.cancelled and 'Try again.' or nil end
    CivJobs.dropCarry()
    return true, res.quality
end

--------------------------------------------------------------------------------
-- Rolled over: hook the winch, keep the cable tension in the green
--------------------------------------------------------------------------------
function Roadside.flipped(veh)
    if not truckNear(veh, 25.0) then return false, 'Bring your truck closer to winch the car.' end
    face(veh)
    if not lib.progressBar({
        duration = 3500, label = 'Hooking up the winch…', canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = Config.Anims.kneel.dict, clip = Config.Anims.kneel.clip },
    }) then return false end
    local res = MG('tension', { title = 'Winch it back onto its wheels', duration = 6 })
    if res.snapped then CivJobs.notify('The cable snapped! Hook it up again.', 'error') end
    if not res.success then return false end
    return true, res.quality
end

--------------------------------------------------------------------------------
-- Body damage: pull the dents, refit the panels
--------------------------------------------------------------------------------
function Roadside.body(veh)
    face(veh)
    anim(Config.Anims.kneel)
    local ok, q = steps({
        function() return MG('pump', { title = 'Pull the dents out', hits = 6, hint = 'Hit SPACE in the green to pull each dent.' }) end,
        function() return MG('torque', { title = 'Refit the panels', count = 3 }) end,
    })
    stopAnim()
    return ok, q
end

--------------------------------------------------------------------------------
-- Nothing wrong: quick safety inspection
--------------------------------------------------------------------------------
function Roadside.inspect(veh)
    face(veh)
    local ok = lib.progressBar({
        duration = 7000, label = 'Safety inspection…', canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = Config.Anims.hood.dict, clip = Config.Anims.hood.clip },
    })
    return ok, 1.0
end

function Roadside.forgetSpares()
    spareAt = {}
end
