# Writing a job add-on

A job is a normal resource that loads the base's addon library and registers itself. The base handles the depot NPC and blip, the rental vehicle and deposit, starting and ending shifts, pay, XP and levels, the hourly cap, the Gigs app, the Job Center and the `/civjobs` on/off toggle. Your add-on only does the gameplay.

## fxmanifest.lua

```lua
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bdev-cj-myjob'

shared_scripts {
    '@ox_lib/init.lua',
    '@bdev-civilian-jobs/addon.lua',
    'config.lua',
}
client_script 'client.lua'
server_script 'server.lua'

dependencies { 'bdev-civilian-jobs', 'ox_lib', 'ox_target' }
```

## Register the job (server)

```lua
CivJobs.register({
    id = 'windowclean',                 -- unique, letters/numbers/_/-
    label = 'Window Cleaner',
    description = 'Clean office windows downtown.',
    icon = 'spray-can',                 -- Font Awesome name (menus) / emoji map in the app
    depot = {
        coords = vec4(-50.0, -800.0, 44.2, 90.0), -- where the depot NPC stands (player position)
        ped = 's_m_y_winclean_01',
        blip = { sprite = 280, color = 3, scale = 0.8 },
        radius = 40.0,                  -- vehicle counts as "returned" inside this
    },
    vehicle = {                         -- optional: leave out for on-foot jobs
        model = 'speedo', label = 'Work Van', deposit = 300, plate = 'WASH',
        spawns = { vec4(-60.0, -790.0, 44.2, 90.0) },
    },
    maxEarnPerHour = 15000,             -- optional, overrides Config.Limits.maxEarnPerHour
    requests = {                        -- optional: let players hire you
        label = 'Window cleaning',
        description = 'Someone cleans your windows.',
        price = 200,                    -- requester pays the worker
        npcPrice = 300,                 -- nil = no NPC fallback
        bonus = 75,                     -- job-paid extra for the worker
        needsVehicle = false,           -- true = requester must be next to a vehicle
    },
})
```

The id is what admins use: `civjobs disable windowclean`. Its default on/off comes from `Config.Jobs[id]` in the base config (or `Config.DefaultEnabled`).

## Server API (`CivJobs.*`)

| Function | Use |
|---|---|
| `onStart(jobId, fn(src, session))` / `onStop(jobId, fn(src, reason))` | Shift started / ended (reason: `quit`, `disabled`, `unavailable`, `disconnect`, `logout`, `shutdown`, `addon`) |
| `session(src, jobId?)` | The player's shift `{ job, netId, startedAt, earned, tasks, level, deposit }` or nil |
| `reward(src, jobId, { pay, xp, label, task })` | Pay for a finished task. Level bonus and hourly cap are applied. Only the add-on that registered the job can pay for it |
| `status(src, text)` | One line shown on the player's Gigs "My shift" tab |
| `vehicle(src)` / `entity(netId)` | Job vehicle entity / entity from a netId |
| `near(src, coords, dist)` / `coords(src)` | Position checks for validation |
| `throttle(src, key, ms)` | Rate-limit a callback |
| `level(src, jobId)` | Player level in that job |
| `endShift(src, reason)` | End the player's shift from your add-on |
| `onRequest(jobId, fn(workerSrc, req))` | A worker accepted a player's request. `req = { id, requester, requesterName, netId, plate, coords, price, note }` |
| `onRequestCancelled(jobId, fn(workerSrc or nil, reqId, req))` | The requester cancelled or left |
| `onNpcRequest(jobId, fn(req))` | Nobody's working: do the job with an NPC, then call `completeNpcRequest` |
| `requestWorking(id)` | Work started; the requester can no longer cancel |
| `completeRequest(id, { pay, xp, label })` | Done: pays the held money and the job bonus to the worker |
| `releaseRequest(id, msg)` / `cancelRequest(id, msg)` | Back to the queue / cancel with refund |
| `completeNpcRequest(id, success)` | NPC finished (`false` = refund) |

**Always validate on the server.** Check `CivJobs.session(src, JOB)`, distances, and time between steps before you call `reward`. Never take a pay amount from the client.

## Client API (`CivJobs.*`)

| Function | Use |
|---|---|
| `onStart(jobId, fn(session))` / `onStop(jobId, fn(reason))` | Your shift started / ended |
| `onRequest(jobId, fn(req))` / `onRequestCancelled(jobId, fn(reqId))` | Request accepted / taken away |
| `current(jobId?)` / `vehicle()` | Your shift / your job vehicle |
| `minigame(name, opts)` | Run a minigame from the kit: returns `{ success, quality, mistakes, cancelled, ... }` |
| `carry(model, opts)` / `dropCarry()` / `isCarrying(model?)` | Carry a prop with an animation (blocks sprint, jump, entering vehicles) |
| `blip(coords, label, sprite, color, route)` / `removeBlip(b)` | Blips with an optional GPS route |
| `playAnim(dict, clip, duration, flag)` / `groundZ(coords)` / `notify(msg, type, title)` | Helpers |

## Minimal example

```lua
-- server.lua
local JOB = 'windowclean'
CivJobs.register(Config.Job)

local windows = {}
CivJobs.onStart(JOB, function(src) windows[src] = 0 end)
CivJobs.onStop(JOB, function(src) windows[src] = nil end)

lib.callback.register('windowclean:done', function(src, spot)
    if not CivJobs.session(src, JOB) or not CivJobs.throttle(src, 'clean', 8000) then return false end
    if not CivJobs.near(src, Config.Spots[spot], 4.0) then return false end
    CivJobs.reward(src, JOB, { pay = 90, xp = 4, label = 'Window cleaned' })
    return true
end)
```

```lua
-- client.lua
local function clean(spot)
    local res = CivJobs.minigame('pump', { title = 'Scrub the window', hits = 5 })
    if res.success then lib.callback.await('windowclean:done', false, spot) end
end
```

## Restarts

- Restarting the **base** fires `bdev-civilian-jobs:ready`, and the library re-registers your job by itself.
- Stopping your **add-on** removes its job, sends its workers home (deposit refunded) and refunds its open requests.
