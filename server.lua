local QBCore = exports['qb-core']:GetCoreObject()

-- Store active stashes to prevent duplicates
local activeStashes = {}

-- Load existing stashes from database on server start
CreateThread(function()
    Wait(2000) -- Wait for database to be ready
    
    -- Clean up expired stashes first
    CleanupExpiredStashes()
    
    -- Load remaining valid stashes
    MySQL.Async.fetchAll('SELECT *, UNIX_TIMESTAMP(expires_at) as expires_unix FROM eskdrop_stashes WHERE expires_at > NOW()', {}, function(results)
        if results then
            for _, stash in ipairs(results) do
                local coords = vector4(stash.coords_x, stash.coords_y, stash.coords_z, stash.heading or 0.0)
                local expiresAt = tonumber(stash.expires_unix)
                local stashType = stash.stash_type or 'spade' -- Default to spade for legacy stashes
                local stashConfig = Config.StashTypes[stashType]
                
                if stashConfig then
                    -- Reconstruct the full stash label with container type
                    local fullStashLabel = stash.owner_name .. "'s " .. stashConfig.label
                    
                    -- Register stash with ox_inventory using proper config and full label
                    exports.ox_inventory:RegisterStash(stash.stash_id, fullStashLabel, stashConfig.slots, stashConfig.weight, false)
                    
                    -- Store in active stashes
                    activeStashes[stash.stash_id] = {
                        owner = stash.owner_citizenid,
                        label = fullStashLabel,
                        coords = coords,
                        created = stash.created_at,
                        expiresAt = expiresAt,
                        stashType = stashType
                    }
                    
                    -- Create stash on all clients (props and client tracking) with full label
                    TriggerClientEvent('eskdrop-spade:client:createStash', -1, stash.stash_id, fullStashLabel, coords, expiresAt)
                    TriggerClientEvent('eskdrop-spade:client:createProp', -1, stash.stash_id, coords, stashType)
                    
                    if Config.Debug then
                        print('^2[eskdrop-spade]^7 Loaded stash: ' .. fullStashLabel .. ' (ID: ' .. stash.stash_id .. ', Type: ' .. stashType .. ')')
                    end
                else
                    if Config.Debug then
                        print('^3[eskdrop-spade]^7 Warning: Unknown stash type "' .. stashType .. '" for stash ID: ' .. stash.stash_id)
                    end
                end
            end
            if Config.Debug then
                print('^2[eskdrop-spade]^7 Loaded ' .. #results .. ' valid stashes from database and spawned props')
            end
        end
    end)
end)

-- Function to clean up expired stashes
function CleanupExpiredStashes()
    MySQL.Async.execute('DELETE FROM eskdrop_stashes WHERE expires_at <= NOW()', {}, function(affectedRows)
        if affectedRows > 0 and Config.Debug then
            print('^3[eskdrop-spade]^7 Cleaned up ' .. affectedRows .. ' expired stashes from database')
        end
    end)
    
    -- Clean up from active stashes in memory
    local currentTime = os.time()
    local removedCount = 0
    
    for stashId, stashData in pairs(activeStashes) do
        if stashData.expiresAt and currentTime >= stashData.expiresAt then
            -- Remove from ox_inventory
            exports.ox_inventory:ClearInventory(stashId)
            
            -- Remove props and client data from all clients
            TriggerClientEvent('eskdrop-spade:client:removeStash', -1, stashId)
            
            -- Remove from active stashes
            activeStashes[stashId] = nil
            removedCount = removedCount + 1
            
            if Config.Debug then
                print('^3[eskdrop-spade]^7 Removed expired stash from memory: ' .. stashId)
            end
        end
    end
    
    if removedCount > 0 and Config.Debug then
        print('^3[eskdrop-spade]^7 Cleaned up ' .. removedCount .. ' expired stashes from memory')
    end
end

-- Periodic cleanup (every 5 minutes)
CreateThread(function()
    while true do
        Wait(300000) -- 5 minutes
        CleanupExpiredStashes()
    end
end)

-- Create useable items for all configured stash types
for itemName, stashConfig in pairs(Config.StashTypes) do
    QBCore.Functions.CreateUseableItem(itemName, function(source, item)
        local src = source
        local Player = QBCore.Functions.GetPlayer(src)
        
        if not Player then return end
        
        if Config.Debug then
            print('^2[eskdrop-spade]^7 ' .. itemName .. ' used by player ' .. src)
        end
        
        -- Remove the item from inventory
        Player.Functions.RemoveItem(itemName, 1)
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[itemName], "remove")
        
        -- Trigger client-side stash creation with stash type
        TriggerClientEvent('eskdrop-spade:client:useStashItem', src, itemName, stashConfig)
    end)
end

-- Testing commands for stash functionality (debug mode only)
if Config.Debug then
    RegisterCommand('shovel', function(source, args, rawCommand)
        local src = source
        local stashType = args[1] or 'spade'
        local stashConfig = Config.StashTypes[stashType]
        
        if stashConfig then
            -- Start the new interactive placement system
            TriggerClientEvent('eskdrop-spade:client:useStashItem', src, stashType, stashConfig)
            if Config.Debug then
                print('^2[eskdrop-spade]^7 Starting interactive placement for ' .. stashType .. ' for player ' .. src)
            end
        else
            TriggerClientEvent('QBCore:Notify', src, 'Invalid stash type. Available: ' .. table.concat(getTableKeys(Config.StashTypes), ', '), 'error')
        end
    end, false)
end

-- Helper function to get table keys
function getTableKeys(tbl)
    local keys = {}
    for key, _ in pairs(tbl) do
        table.insert(keys, key)
    end
    return keys
end

-- Handle stash item usage and get player name
RegisterNetEvent('eskdrop-spade:client:getPlayerName', function(coords, propHandle, stashType)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    local citizenid = Player.PlayerData.citizenid
    local stashConfig = Config.StashTypes[stashType]
    
    if not stashConfig then
        TriggerClientEvent('QBCore:Notify', src, 'Invalid stash type', 'error')
        return
    end
    
    -- Query the database for player character info
    MySQL.Async.fetchScalar('SELECT charinfo FROM players WHERE citizenid = ?', {citizenid}, function(result)
        if result then
            local charinfo = json.decode(result)
            local firstname = charinfo.firstname or 'Unknown'
            local lastname = charinfo.lastname or 'Player'
            
            -- Create unique stash identifier
            local stashId = stashType .. '_stash_' .. citizenid .. '_' .. os.time()
            local stashLabel = firstname .. ' ' .. lastname .. "'s " .. stashConfig.label
            local currentTime = os.time()
            local expiresAt = currentTime + stashConfig.expiration_time
            
            -- Register the stash with ox_inventory using stash-specific properties
            exports.ox_inventory:RegisterStash(stashId, stashLabel, stashConfig.slots, stashConfig.weight, false)
            
            -- Store stash info in memory
            activeStashes[stashId] = {
                owner = citizenid,
                label = stashLabel,
                coords = coords,
                created = currentTime,
                expiresAt = expiresAt,
                stashType = stashType
            }
            
            -- Save stash to database with expiration time and stash type
            MySQL.Async.execute('INSERT INTO eskdrop_stashes (stash_id, owner_citizenid, owner_name, coords_x, coords_y, coords_z, heading, expires_at, stash_type) VALUES (?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?), ?)', {
                stashId,
                citizenid,
                firstname .. ' ' .. lastname,
                coords.x,
                coords.y,
                coords.z,
                coords.w or 0.0,
                expiresAt,
                stashType
            }, function(affectedRows)
                if Config.Debug then
                    if affectedRows > 0 then
                        print('^2[eskdrop-spade]^7 Saved stash to database: ' .. stashLabel .. ' (ID: ' .. stashId .. ') - Expires in ' .. stashConfig.expiration_time .. ' seconds')
                    else
                        print('^1[eskdrop-spade]^7 Failed to save stash to database: ' .. stashId)
                    end
                end
            end)
            
            -- Send stash info to client with timer information and prop handle
            TriggerClientEvent('eskdrop-spade:client:createStash', src, stashId, stashLabel, coords, expiresAt, propHandle)
            
            if Config.Debug then
                print('^2[eskdrop-spade]^7 Created ' .. stashConfig.label .. ' for ' .. firstname .. ' ' .. lastname .. ' (ID: ' .. stashId .. ')')
            end
        else
            TriggerClientEvent('QBCore:Notify', src, 'Failed to retrieve character information', 'error')
        end
    end)
end)

-- Handle stash opening
RegisterNetEvent('eskdrop-spade:server:openStash', function(stashId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    if not Player then return end
    
    -- Check if stash exists and player is owner
    if activeStashes[stashId] and activeStashes[stashId].owner == Player.PlayerData.citizenid then
        -- Double-check if stash has expired
        local currentTime = os.time()
        if activeStashes[stashId].expiresAt and currentTime >= activeStashes[stashId].expiresAt then
            TriggerClientEvent('QBCore:Notify', src, 'This stash has expired and is no longer accessible', 'error')
            if Config.Debug then
                print('^1[eskdrop-spade]^7 Player ' .. Player.PlayerData.name .. ' tried to access expired stash: ' .. stashId)
            end
            
            -- Trigger immediate cleanup since it somehow wasn't cleaned up yet
            TriggerEvent('eskdrop-spade:server:expireStash', stashId)
            return
        end
        
        -- Update last accessed time in database
        MySQL.Async.execute('UPDATE eskdrop_stashes SET last_accessed = CURRENT_TIMESTAMP WHERE stash_id = ?', {stashId})
        
        -- Open the stash inventory
        exports.ox_inventory:forceOpenInventory(src, 'stash', stashId)
        
        if Config.Debug then
            print('^2[eskdrop-spade]^7 Player ' .. Player.PlayerData.name .. ' opened stash: ' .. stashId)
        end
    else
        TriggerClientEvent('QBCore:Notify', src, 'You cannot access this stash', 'error')
        if Config.Debug then
            print('^3[eskdrop-spade]^7 Player ' .. Player.PlayerData.name .. ' tried to access unauthorized stash: ' .. stashId)
        end
    end
end)

-- Admin command to list all stashes (debug mode only)
if Config.Debug then
    RegisterCommand('liststashes', function(source, args, rawCommand)
        local src = source
        local Player = QBCore.Functions.GetPlayer(src)
        
        if not Player then return end
        
        -- Check if player is admin (you can modify this permission check)
        if Player.PlayerData.job.name == 'admin' or src == 0 then
            MySQL.Async.fetchAll('SELECT * FROM eskdrop_stashes ORDER BY created_at DESC', {}, function(results)
                if results and #results > 0 then
                    print('^2[eskdrop-spade]^7 === STASH LIST ===')
                    for _, stash in ipairs(results) do
                        local stashType = stash.stash_type or 'unknown'
                        print('^3ID:^7 ' .. stash.stash_id)
                        print('^3Type:^7 ' .. stashType)
                        print('^3Owner:^7 ' .. stash.owner_name .. ' (' .. stash.owner_citizenid .. ')')
                        print('^3Location:^7 ' .. stash.coords_x .. ', ' .. stash.coords_y .. ', ' .. stash.coords_z .. ' (heading: ' .. (stash.heading or 0.0) .. ')')
                        print('^3Created:^7 ' .. stash.created_at)
                        print('---')
                    end
                    print('^2[eskdrop-spade]^7 Total stashes: ' .. #results)
                else
                    print('^1[eskdrop-spade]^7 No stashes found in database')
                end
            end)
        else
            TriggerClientEvent('QBCore:Notify', src, 'You do not have permission to use this command', 'error')
        end
    end, false)
end

-- Handle immediate stash expiration (triggered by client timer)
RegisterNetEvent('eskdrop-spade:server:expireStash', function(stashId)
    local src = source
    
    if Config.Debug then
        print('^1[eskdrop-spade]^7 Immediate stash expiration triggered for: ' .. stashId)
    end
    
    -- Check if stash exists
    if activeStashes[stashId] then
        -- Remove from database immediately
        MySQL.Async.execute('DELETE FROM eskdrop_stashes WHERE stash_id = ?', {stashId}, function(affectedRows)
            if affectedRows > 0 and Config.Debug then
                print('^3[eskdrop-spade]^7 Removed expired stash from database: ' .. stashId)
            end
        end)
        
        -- Clear ox_inventory stash
        exports.ox_inventory:ClearInventory(stashId)
        if Config.Debug then
            print('^3[eskdrop-spade]^7 Cleared ox_inventory for expired stash: ' .. stashId)
        end
        
        -- Remove from server memory
        activeStashes[stashId] = nil
        
        -- Remove from all clients (props, text, interaction)
        TriggerClientEvent('eskdrop-spade:client:removeStash', -1, stashId)
        
        if Config.Debug then
            print('^1[eskdrop-spade]^7 Stash ' .. stashId .. ' has been completely removed due to expiration')
        end
    else
        if Config.Debug then
            print('^3[eskdrop-spade]^7 Attempted to expire non-existent stash: ' .. stashId)
        end
    end
end)

-- Send timer updates to all nearby players
CreateThread(function()
    while true do
        Wait(10000) -- Update every 10 seconds
        
        for stashId, stashData in pairs(activeStashes) do
            if stashData.expiresAt then
                -- Send timer update to all players near this stash
                TriggerClientEvent('eskdrop-spade:client:updateTimer', -1, stashId, stashData.expiresAt)
            end
        end
    end
end)