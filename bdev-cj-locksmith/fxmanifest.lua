fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'bdev-cj-locksmith'
author 'bdev'
description 'Locksmith job addon for bdev-civilian-jobs: car and house lockouts, lock changes, safes and key cutting with minigames, player call-outs (qs-housing) and an NPC locksmith fallback'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    '@bdev-civilian-jobs/addon.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
    'client/npc_service.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
}

dependencies {
    'bdev-civilian-jobs',
    'ox_lib',
    'ox_target',
    'oxmysql',
}
