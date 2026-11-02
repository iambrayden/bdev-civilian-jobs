fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'bdev-cj-bus'
author 'bdev'
description 'Bus Driver job addon for bdev-civilian-jobs: timetabled routes, stop precision, NPC passengers with fares and pass checks, ride quality, and real players riding'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    '@bdev-civilian-jobs/addon.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
    'client/rider.lua',
}

server_script 'server.lua'

dependencies {
    'bdev-civilian-jobs',
    'ox_lib',
    'ox_target',
}
