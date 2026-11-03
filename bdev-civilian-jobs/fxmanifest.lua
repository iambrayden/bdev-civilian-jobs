fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'bdev-civilian-jobs'
author 'bdev'
description 'Public civilian jobs framework for Qbox: job center, rentals, pay, XP, player service requests with NPC fallback, minigames, a Gigs phone app and drop-in job addons'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    '@qbx_core/modules/lib.lua',
    'config.lua',
    'shared/utils.lua',
}

client_scripts {
    '@qbx_core/modules/playerdata.lua',
    'client/main.lua',
    'client/depots.lua',
    'client/jobcenter.lua',
    'client/requests.lua',
    'client/minigames.lua',
    'client/phone.lua',
    'client/app.lua',
    'client/admin.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/stats.lua',
    'server/registry.lua',
    'server/sessions.lua',
    'server/requests.lua',
    'server/app.lua',
    'server/admin.lua',
}

-- Minigames run in this resource's own NUI page.
ui_page 'html/minigame/index.html'

files {
    -- addons load this with '@bdev-civilian-jobs/addon.lua'
    'addon.lua',
    'html/minigame/index.html',
    'html/minigame/style.css',
    'html/minigame/game.js',
    -- the Gigs phone app (loaded by qs-smartphone in an iframe)
    'html/app/index.html',
    'html/app/style.css',
    'html/app/app.js',
    'html/app/icon.png',
}

dependencies {
    'qbx_core',
    'ox_lib',
    'oxmysql',
    'ox_target',
}
