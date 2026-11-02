-- Per-player, per-job XP / earnings and worker ratings.

local cache = {} -- citizenid -> job -> { xp, completed, earned }
local ratings = {} -- citizenid -> job -> { total, count }

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `civjobs_stats` (
            `citizenid` VARCHAR(50) NOT NULL,
            `job` VARCHAR(50) NOT NULL,
            `xp` INT NOT NULL DEFAULT 0,
            `completed` INT NOT NULL DEFAULT 0,
            `earned` BIGINT NOT NULL DEFAULT 0,
            `rating_total` INT NOT NULL DEFAULT 0,
            `rating_count` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`citizenid`, `job`)
        )
    ]])
end)

local function load(cid, job)
    cache[cid] = cache[cid] or {}
    ratings[cid] = ratings[cid] or {}
    if cache[cid][job] then return end
    local row = MySQL.single.await(
        'SELECT xp, completed, earned, rating_total, rating_count FROM civjobs_stats WHERE citizenid = ? AND job = ?',
        { cid, job })
    cache[cid][job] = {
        xp = row and row.xp or 0,
        completed = row and row.completed or 0,
        earned = row and row.earned or 0,
    }
    ratings[cid][job] = {
        total = row and row.rating_total or 0,
        count = row and row.rating_count or 0,
    }
end

function CJ.getStats(cid, job)
    load(cid, job)
    return cache[cid][job]
end

--- Adds XP / earnings / completed count. Returns the level before and after.
function CJ.addStats(cid, job, xp, earned, completed)
    local s = CJ.getStats(cid, job)
    local before = CJ.levelFromXp(s.xp)
    s.xp = s.xp + xp
    s.earned = s.earned + earned
    s.completed = s.completed + completed
    MySQL.prepare([[
        INSERT INTO civjobs_stats (citizenid, job, xp, completed, earned) VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE xp = xp + VALUES(xp), completed = completed + VALUES(completed), earned = earned + VALUES(earned)
    ]], { cid, job, xp, completed, earned })
    return before, CJ.levelFromXp(s.xp)
end

--- Average rating (1-5) or nil if nobody has rated this worker yet.
function CJ.getRating(cid, job)
    load(cid, job)
    local r = ratings[cid][job]
    if r.count == 0 then return nil, 0 end
    return math.floor(r.total / r.count * 10 + 0.5) / 10, r.count
end

function CJ.addRating(cid, job, stars)
    load(cid, job)
    local r = ratings[cid][job]
    r.total = r.total + stars
    r.count = r.count + 1
    MySQL.prepare([[
        INSERT INTO civjobs_stats (citizenid, job, rating_total, rating_count) VALUES (?, ?, ?, 1)
        ON DUPLICATE KEY UPDATE rating_total = rating_total + VALUES(rating_total), rating_count = rating_count + 1
    ]], { cid, job, stars })
end

AddEventHandler('playerDropped', function()
    local cid = CJ.citizenid(source)
    if cid then
        cache[cid] = nil
        ratings[cid] = nil
    end
end)
