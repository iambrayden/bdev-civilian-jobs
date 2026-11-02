fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'bdev-cj-repo'
author 'bdev'
description 'Repo Agent job addon for bdev-civilian-jobs: NPC repossession cases with search areas, witnesses, a plate reader, slim jim + hotwire or flatbed, and owner confrontations'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    '@bdev-civilian-jobs/addon.lua',
    'config.lua',
}

client_script 'client/main.lua'
server_script 'server.lua'

dependencies {
    'bdev-civilian-jobs',
    'ox_lib',
    'ox_target',
}
