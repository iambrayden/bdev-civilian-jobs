fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'bdev-cj-foodtruck'
author 'bdev'
description 'Street Food Vendor job addon for bdev-civilian-jobs: taco truck with hot spots, NPC customer queues, grill and assemble minigames, supplies, and real players buying real food'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    '@bdev-civilian-jobs/addon.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
    'client/customer.lua',
}

server_script 'server.lua'

dependencies {
    'bdev-civilian-jobs',
    'ox_lib',
    'ox_target',
}
