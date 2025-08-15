local QBCore = exports['qb-core']:GetCoreObject()

-- Store active stash props and their data
local activeStashProps = {}
local renderingStashCount = 0 -- Track how many stashes are currently rendering

-- Handle stash item usage
RegisterNetEvent('eskdrop-spade:client:useStashItem', function(stashType, stashConfig)
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    local heading = GetEntityHeading(playerPed)
    
    -- Disable player controls during animation
    SetPlayerControl(PlayerId(), false, 0)
    
    -- Load animation dictionary
    RequestAnimDict(stashConfig.animation.dict)
    while not HasAnimDictLoaded(stashConfig.animation.dict) do
        Wait(100)
    end
    
    -- Play animation
    TaskPlayAnim(playerPed, stashConfig.animation.dict, stashConfig.animation.name, 8.0, -8.0, stashConfig.animation.duration, 1, 0, false, false, false)
    
    -- Show notification
    QBCore.Functions.Notify('Creating ' .. stashConfig.label .. '...', 'primary', stashConfig.animation.duration)
    
    -- Wait for animation to complete
    Wait(stashConfig.animation.duration)
    
    -- Clear animation and restore controls
    ClearPedTasks(playerPed)
    SetPlayerControl(PlayerId(), true, 1)
    
    -- Calculate prop position (slightly in front of player)
    local propCoords = GetOffsetFromEntityInWorldCoords(playerPed, 0.0, 1.0, -0.5)
    
    -- Create the stash prop using config-specific prop
    local propModel = GetHashKey(stashConfig.prop)
    RequestModel(propModel)
    while not HasModelLoaded(propModel) do
        Wait(100)
    end
    
    local prop = CreateObject(propModel, propCoords.x, propCoords.y, propCoords.z, true, true, true)
    PlaceObjectOnGroundProperly(prop)
    SetEntityHeading(prop, heading)
    SetEntityAsMissionEntity(prop, true, true)
    FreezeEntityPosition(prop, true)
    
    -- Set model as no longer needed
    SetModelAsNoLongerNeeded(propModel)
    
    -- Request player name from server (this will create the stash and store the prop handle)
    TriggerServerEvent('eskdrop-spade:client:getPlayerName', propCoords, prop, stashType)
    
    if Config.Debug then
        print('^2[eskdrop-spade]^7 Created ' .. stashType .. ' prop and sent coordinates to server')
    end
end)

-- Legacy spade support (for backward compatibility)
RegisterNetEvent('eskdrop-spade:client:useSpade', function()
    local spadeConfig = Config.StashTypes['spade']
    if spadeConfig then
        TriggerEvent('eskdrop-spade:client:useStashItem', 'spade', spadeConfig)
    else
        if Config.Debug then
            print('^1[eskdrop-spade]^7 Error: Spade config not found!')
        end
    end
end)

-- Create stash with 3D text and interaction
RegisterNetEvent('eskdrop-spade:client:createStash', function(stashId, stashLabel, coords, expiresAt, propHandle)
    -- Store stash data
    activeStashProps[stashId] = {
        coords = coords,
        label = stashLabel,
        active = true,
        isNear = false,
        renderActive = false,
        expiresAt = expiresAt,
        propHandle = propHandle or nil
    }
    
    -- Create interaction zone using qb-target or similar
    CreateStashInteraction(stashId, coords, stashLabel)
    
    -- Start optimized proximity checking thread (runs less frequently)
    CreateThread(function()
        while activeStashProps[stashId] and activeStashProps[stashId].active do
            local playerCoords = GetEntityCoords(PlayerPedId())
            local distance = #(playerCoords - coords)
            local wasNear = activeStashProps[stashId].isNear
            
            if distance < Config.Text3D.distance then
                activeStashProps[stashId].isNear = true
                -- Start rendering thread only when player gets near and under limit
                if not wasNear and not activeStashProps[stashId].renderActive then
                    if renderingStashCount < Config.Text3D.max_concurrent_texts then
                        activeStashProps[stashId].renderActive = true
                        renderingStashCount = renderingStashCount + 1
                        StartTextRenderingThread(stashId, coords, stashLabel)
                    end
                end
            else
                if activeStashProps[stashId].renderActive then
                    renderingStashCount = math.max(0, renderingStashCount - 1)
                end
                activeStashProps[stashId].isNear = false
                activeStashProps[stashId].renderActive = false
            end
            
            Wait(Config.Text3D.proximity_check_interval) -- Configurable proximity check interval
        end
    end)
    
    QBCore.Functions.Notify('Stash created: ' .. stashLabel, 'success')
end)

-- Handle prop creation for loaded stashes
RegisterNetEvent('eskdrop-spade:client:createProp', function(stashId, coords, stashType)
    stashType = stashType or 'spade' -- Default to spade for legacy stashes
    local stashConfig = Config.StashTypes[stashType]
    
    if not stashConfig then
        if Config.Debug then
            print('^1[eskdrop-spade]^7 Error: Unknown stash type "' .. stashType .. '" for prop creation')
        end
        return
    end
    
    local propModel = GetHashKey(stashConfig.prop)
    RequestModel(propModel)
    while not HasModelLoaded(propModel) do
        Wait(100)
    end
    
    -- Create prop at specified coordinates
    local prop = CreateObject(propModel, coords.x, coords.y, coords.z, true, true, true)
    PlaceObjectOnGroundProperly(prop)
    SetEntityAsMissionEntity(prop, true, true)
    FreezeEntityPosition(prop, true)
    
    -- Store prop handle for cleanup
    if activeStashProps[stashId] then
        activeStashProps[stashId].propHandle = prop
    end
    
    -- Set model as no longer needed
    SetModelAsNoLongerNeeded(propModel)
    
    if Config.Debug then
        print('^2[eskdrop-spade]^7 Created ' .. stashType .. ' prop for existing stash: ' .. stashId)
    end
end)

-- Create interaction for stash (now handled by E key detection)
function CreateStashInteraction(stashId, coords, stashLabel)
    -- Interaction is now handled by the E key detection thread
    -- No additional setup needed
end

-- Open stash event
RegisterNetEvent('eskdrop-spade:client:openStash', function(data)
    local stashId = data.stashId
    if activeStashProps[stashId] then
        TriggerServerEvent('eskdrop-spade:server:openStash', stashId)
    end
end)

-- NUI-based text rendering (only method)
function StartTextRenderingThread(stashId, coords, stashLabel)
    StartNUITextRendering(stashId, coords, stashLabel)
end

-- NUI-based text rendering
function StartNUITextRendering(stashId, coords, stashLabel)
    CreateThread(function()
        -- Show NUI text initially
        local textCoords = vector3(coords.x, coords.y, coords.z + Config.Text3D.height_offset)
        ShowNUIText(stashId, stashLabel, textCoords)
        
        while activeStashProps[stashId] and activeStashProps[stashId].renderActive and activeStashProps[stashId].isNear do
            if activeStashProps[stashId].isNear then
                -- Update NUI text position
                UpdateNUIText(stashId, textCoords)
                Wait(Config.Text3D.nui_update_frequency)
            else
                break
            end
        end
        
        -- Hide NUI text when done
        HideNUIText(stashId)
        
        if activeStashProps[stashId] then
            activeStashProps[stashId].renderActive = false
            renderingStashCount = math.max(0, renderingStashCount - 1)
        end
    end)
end

-- NUI Text Functions
function ShowNUIText(id, stashLabel, coords)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if onScreen then
        SendNUIMessage({
            action = 'show',
            id = id,
            text = stashLabel, -- This will be the stash owner's name
            x = x * 1920, -- Convert to screen coordinates
            y = y * 1080
        })
        
        -- Send timer information if available
        if activeStashProps[id] and activeStashProps[id].expiresAt then
            SendNUIMessage({
                action = 'updateTimer',
                id = id,
                expiresAt = activeStashProps[id].expiresAt
            })
        end
    end
end

function UpdateNUIText(id, coords)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if onScreen then
        SendNUIMessage({
            action = 'update',
            id = id,
            x = x * 1920,
            y = y * 1080
        })
    end
end

-- Handle timer updates from server
RegisterNetEvent('eskdrop-spade:client:updateTimer', function(stashId, expiresAt)
    if activeStashProps[stashId] then
        activeStashProps[stashId].expiresAt = expiresAt
        
        -- Update NUI timer if this stash is currently displayed
        if activeStashProps[stashId].renderActive then
            SendNUIMessage({
                action = 'updateTimer',
                id = stashId,
                expiresAt = expiresAt
            })
        end
    end
end)

function HideNUIText(id)
    SendNUIMessage({
        action = 'hide',
        id = id
    })
end

-- E Key press detection and visual feedback
CreateThread(function()
    while true do
        Wait(0)
        
        -- Check if E key is pressed (control 38)
        if IsControlJustPressed(0, 38) then
            local playerCoords = GetEntityCoords(PlayerPedId())
            
            -- Find all stashes that are near and have visible text
            local nearbyStashes = {}
            for stashId, stashData in pairs(activeStashProps) do
                if stashData.isNear then
                    local distance = #(playerCoords - stashData.coords)
                    if distance < Config.Text3D.distance then
                        table.insert(nearbyStashes, {
                            stashId = stashId,
                            stashData = stashData,
                            distance = distance
                        })
                    end
                end
            end
            
            -- If we found nearby stashes, open the closest one
            if #nearbyStashes > 0 then
                -- Sort by distance to find the closest stash
                table.sort(nearbyStashes, function(a, b)
                    return a.distance < b.distance
                end)
                
                local closestStash = nearbyStashes[1]
                local stashId = closestStash.stashId
                local stashData = closestStash.stashData
                
                if Config.Debug then
                    print('^6[eskdrop-spade]^7 Found ' .. #nearbyStashes .. ' nearby stashes, opening closest: ' .. stashId .. ' (distance: ' .. string.format("%.2f", closestStash.distance) .. 'm)')
                end
                
                -- Trigger visual key press effect in NUI for the closest stash
                SendNUIMessage({
                    action = 'keypress',
                    id = stashId
                })
                
                -- Check if stash exists and is expired before opening
                if activeStashProps[stashId] then
                    local currentTime = GetCloudTimeAsInt() -- FiveM client-side Unix timestamp
                    local expiresAt = activeStashProps[stashId].expiresAt
                    
                    -- Debug info
                    if Config.Debug then
                        print('^5[eskdrop-spade]^7 Debug - Current time: ' .. currentTime .. ', Expires at: ' .. tostring(expiresAt))
                    end
                    
                    if expiresAt and currentTime >= expiresAt then
                        QBCore.Functions.Notify('This stash has expired and cannot be accessed', 'error')
                        if Config.Debug then
                            print('^1[eskdrop-spade]^7 Attempted to open expired stash: ' .. stashId)
                        end
                    else
                        -- Open the closest stash
                        TriggerServerEvent('eskdrop-spade:server:openStash', stashId)
                        if Config.Debug then
                            print('^2[eskdrop-spade]^7 Opening closest stash: ' .. stashId .. ' at distance ' .. string.format("%.2f", closestStash.distance) .. 'm')
                        end
                    end
                else
                    if Config.Debug then
                        print('^1[eskdrop-spade]^7 Error: activeStashProps[' .. stashId .. '] does not exist!')
                    end
                    -- Try to open anyway (fallback)
                    TriggerServerEvent('eskdrop-spade:server:openStash', stashId)
                end
            elseif Config.Debug then
                print('^3[eskdrop-spade]^7 No nearby stashes found within interaction range')
            end
        end
    end
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        -- Clean up all active stash props
        for stashId, stashData in pairs(activeStashProps) do
            if GetResourceState('qb-target') == 'started' then
                exports['qb-target']:RemoveZone(stashId)
            end
            
            -- Clean up NUI text
            HideNUIText(stashId)
            
            -- Delete prop if it exists
            if stashData.propHandle and DoesEntityExist(stashData.propHandle) then
                DeleteEntity(stashData.propHandle)
            end
            
            activeStashProps[stashId] = nil
        end
        
        -- Clear all NUI text
        SendNUIMessage({action = 'clear'})
    end
end)

-- Remove stash (when expired)
RegisterNetEvent('eskdrop-spade:client:removeStash', function(stashId)
    if activeStashProps[stashId] then
        -- Remove qb-target zone
        if GetResourceState('qb-target') == 'started' then
            exports['qb-target']:RemoveZone(stashId)
        end
        
        -- Hide NUI text
        HideNUIText(stashId)
        
        -- Delete prop if it exists
        if activeStashProps[stashId].propHandle and DoesEntityExist(activeStashProps[stashId].propHandle) then
            DeleteEntity(activeStashProps[stashId].propHandle)
        end
        
        -- Remove from active stashes
        activeStashProps[stashId] = nil
        
        if Config.Debug then
            print('^3[eskdrop-spade]^7 Removed expired stash: ' .. stashId)
        end
    end
end)

-- Handle NUI callback for stash expiration
RegisterNUICallback('stashExpired', function(data, cb)
    local stashId = data.stashId
    if Config.Debug then
        print('^1[eskdrop-spade]^7 Stash expired (client-side): ' .. stashId)
    end
    
    -- Immediately trigger server-side expiration cleanup
    TriggerServerEvent('eskdrop-spade:server:expireStash', stashId)
    
    cb('ok')
end)