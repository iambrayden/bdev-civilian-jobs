CJ = CJ or {}

function CJ.money(n)
    n = math.floor(tonumber(n) or 0)
    local s = tostring(math.abs(n))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    if out:sub(1, 1) == ',' then out = out:sub(2) end
    return (n < 0 and '-' or '') .. Config.Currency .. out
end

function CJ.duration(sec)
    sec = math.max(0, math.floor(sec or 0))
    if sec >= 3600 then
        return ('%dh %02dm'):format(sec // 3600, (sec % 3600) // 60)
    elseif sec >= 60 then
        return ('%dm %02ds'):format(sec // 60, sec % 60)
    end
    return ('%ds'):format(sec)
end

function CJ.clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

function CJ.levelFromXp(xp)
    xp = xp or 0
    local level = 1
    for i, need in ipairs(Config.Levels.xp) do
        if xp >= need then level = i end
    end
    return level
end

--- { level, xp, current = xp at the start of this level, next = xp for the next level (nil at max) }
function CJ.levelInfo(xp)
    xp = xp or 0
    local level = CJ.levelFromXp(xp)
    return {
        level = level,
        xp = xp,
        current = Config.Levels.xp[level] or 0,
        next = Config.Levels.xp[level + 1],
    }
end

function CJ.payMultiplier(level)
    return 1.0 + math.max(0, (level or 1) - 1) * Config.Levels.payBonus
end

function CJ.dist(a, b)
    return #(vec3(a.x, a.y, a.z) - vec3(b.x, b.y, b.z))
end
