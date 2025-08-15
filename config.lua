Config = {}

-- Debug mode configuration
Config.Debug = true -- Set to 'true' to enable debug commands and prints

-- Configurable Stash Types
Config.StashTypes = {
    ['spade'] = {
        label = 'Buried Stash',
        prop = 'v_res_fa_shoebox2',
        slots = 50,
        weight = 100000, -- 100kg in grams
        expiration_time = 3600, -- 1 hour
        animation = {
            dict = 'amb@world_human_gardener_plant@male@base',
            name = 'base',
            duration = 5000 -- 5 seconds
        }
    },
    ['small_crate'] = {
        label = 'Small Crate',
        prop = 'v_ind_meatboxsml',
        slots = 20,
        weight = 25000, -- 25kg in grams
        expiration_time = 1800, -- 30 minutes
        animation = {
            dict = 'mp_common',
            name = 'givetake1_a',
            duration = 3000 -- 3 seconds
        }
    },
    ['medium_box'] = {
        label = 'Storage Box',
        prop = 'prop_box_wood02a_pu',
        slots = 35,
        weight = 60000, -- 60kg in grams
        expiration_time = 2700, -- 45 minutes
        animation = {
            dict = 'mp_common',
            name = 'givetake1_a',
            duration = 4000 -- 4 seconds
        }
    },
    ['large_container'] = {
        label = 'Large Container',
        prop = 'prop_container_01a',
        slots = 75,
        weight = 150000, -- 150kg in grams
        expiration_time = 5400, -- 1.5 hours
        animation = {
            dict = 'amb@world_human_hammering@male@base',
            name = 'base',
            duration = 6000 -- 6 seconds
        }
    }
}

-- 3D Text configuration (NUI-based only)
Config.Text3D = {
    distance = 10.0, -- Distance to show 3D text
    height_offset = 0.5, -- Height above the prop
    proximity_check_interval = 500, -- How often to check proximity (ms)
    max_concurrent_texts = 5, -- Maximum number of 3D texts to render simultaneously
    nui_update_frequency = 50 -- How often to update NUI text position (ms)
}