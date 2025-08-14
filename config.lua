Config = {}

-- Item configuration
Config.SpadeItem = 'spade'

-- Prop configuration
Config.StashProp = 'v_res_fa_shoebox2'

-- Animation configuration
Config.Animation = {
    dict = 'amb@world_human_gardener_plant@male@base',
    name = 'base',
    duration = 5000 -- 5 seconds
}

-- 3D Text configuration (NUI-based only)
Config.Text3D = {
    distance = 10.0, -- Distance to show 3D text
    height_offset = 0.5, -- Height above the prop
    proximity_check_interval = 500, -- How often to check proximity (ms)
    max_concurrent_texts = 5, -- Maximum number of 3D texts to render simultaneously
    nui_update_frequency = 10 -- How often to update NUI text position (ms)
}

-- Stash configuration
Config.Stash = {
    slots = 50,
    weight = 100000, -- 100kg
    expiration_time = 3600 -- Time in seconds until stash expires (3600 = 1 hour)
}
