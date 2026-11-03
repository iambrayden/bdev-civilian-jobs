fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'bdev-cj-roadside'
author 'bdev'
description 'Roadside Assistance job addon for bdev-civilian-jobs: flats, jump starts, fuel, coolant and rollovers with minigames, player call-outs and an NPC mechanic fallback'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    '@bdev-civilian-jobs/addon.lua',
    'config.lua',
}

client_scripts {
    'client/fixes.lua',
    'client/repairs.lua',
    'client/main.lua',
    'client/npc_service.lua',
}

server_script 'server.lua'

dependencies {
    'bdev-civilian-jobs',
    'ox_lib',
    'ox_target',
}
