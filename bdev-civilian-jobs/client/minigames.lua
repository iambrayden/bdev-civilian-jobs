--[[
    Minigame kit. Any job addon can use it:

        local res = exports['bdev-civilian-jobs']:Minigame('torque', { title = 'Tighten the lug nuts', count = 5 })
        if res.success then ... end   -- res.quality is 0.0 - 1.0, res.mistakes, res.cancelled

    Games: pump, nuts, torque, wiring, pour, tension (see docs/MINIGAMES.md for options).
    opts.difficulty is 0.0 (easy) - 1.0 (hard), default 0.5. It is eased by the player's
    level in the job they're working.
]]

local pending

function CJ.minigame(name, opts)
    if pending then return { success = false, cancelled = true, quality = 0, mistakes = 0 } end
    opts = opts or {}
    local level = CJ.Current and CJ.Current.level or 1
    local ease = math.max(0, level - 1) * Config.Levels.minigameEase
    opts.difficulty = CJ.clamp((tonumber(opts.difficulty) or 0.5) - ease, 0.05, 1.0)

    local id = math.random(1, 999999999)
    pending = { id = id, p = promise.new() }
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'start', id = id, game = name, opts = opts })
    local res = Citizen.Await(pending.p)
    pending = nil
    SetNuiFocus(false, false)
    if type(res) ~= 'table' then res = { success = false, cancelled = true } end
    res.quality = tonumber(res.quality) or 0
    res.mistakes = tonumber(res.mistakes) or 0
    return res
end

function CJ.cancelMinigame()
    if pending then
        SendNUIMessage({ action = 'stop' })
        pending.p:resolve({ success = false, cancelled = true })
    end
end

RegisterNUICallback('minigame:done', function(data, cb)
    cb(1)
    if pending and data and data.id == pending.id then pending.p:resolve(data) end
end)

exports('Minigame', CJ.minigame)
exports('CancelMinigame', CJ.cancelMinigame)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and pending then SetNuiFocus(false, false) end
end)
