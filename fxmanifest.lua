fx_version 'cerulean'
game 'gta5'

author 'eskdrop'
description 'Spade Stash Resource - QB-Core compatible with OX_INVENTORY v2.41.0'
version '1.1.0'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

-- NUI files for optional NUI-based 3D text
ui_page 'html/index.html'

files {
    'html/index.html'
}

dependencies {
    'qb-core',
    'ox_inventory',
    'oxmysql'
}