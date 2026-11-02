# Minigame kit

Any resource can run these:

```lua
local res = exports['bdev-civilian-jobs']:Minigame('torque', { title = 'Tighten the bolts', count = 4 })
-- add-ons can use CivJobs.minigame(name, opts)
if res.success then
    print(res.quality)   -- 0.0 - 1.0, use it for tips and ratings
end
-- res.mistakes, res.cancelled (ESC), res.timeout
```

**Common options:** `title`, `hint`, `difficulty` (0.0 easy to 1.0 hard, default 0.5), `misses` (mistakes allowed before failing, default 3), `time` (seconds, 0 = no timer).

The difficulty is eased by the player's level in the job they're working: `Config.Levels.minigameEase`, 4% per level by default.

| Game | Controls | Options | Used for |
|---|---|---|---|
| `pump` | SPACE when the needle is in the green | `hits` (5) | Raising the jack, pulling dents |
| `nuts` | Click the lug nuts in a star (criss-cross) pattern | `count` (4-8, default 5), `action` (`Loosen` / `Tighten`) | Wheel changes |
| `torque` | Hold SPACE, release inside the band | `count` (4) | Tightening bolts and wheels |
| `wiring` | Click a left item, then its right match | `mode = 'match'`: `count` (3-8). `mode = 'sequence'`: `clamps`, `terminals`, `order`; returns `shock = true` after a wrong connection | Wiring harness, jump starts |
| `pour` | Hold SPACE to pour, ENTER when done | `label`, `color` | Fuel, coolant |
| `tension` | Hold SPACE to winch, keep the needle in the green | `duration` (seconds in the green, default 6); returns `snapped = true` if it hit red | Winching cars upright |

Try one in a browser: open `bdev-civilian-jobs/html/minigame/index.html?game=wiring`.

![nuts](screenshots/mg-nuts.png)
![wiring](screenshots/mg-wiring.png)
