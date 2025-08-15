local QBCore = exports['qb-core']:GetCoreObject()

-- Placement system state
local PlacementData = {
    active = false,
    phase = 'none', -- 'positioning', 'heading', 'waiting_build'
    stashType = nil,
    stashConfig = nil,
    previewProp = nil,
    finalCoords = nil,
    heading = 0.0,
    originalHeading = 0.0
}

-- Store placed but not built stashes
local placedStashes = {}

-- Start the placement system
function StartPlacementSystem(stashType, stashConfig)
    if PlacementData.active then
        QBCore.Functions.Notify('Already in placement mode', 'error')
        return
    end
    
    PlacementData.active = true
    PlacementData.phase = 'positioning'
    PlacementData.stashType = stashType
    PlacementData.stashConfig = stashConfig
    PlacementData.heading = GetEntityHeading(PlayerPedId())
    PlacementData.originalHeading = PlacementData.heading
    
    -- Create preview prop
    CreatePreviewProp()
    
    -- Enable NUI focus for mouse movement
    SetNuiFocus(true, false)
    
    -- Start positioning thread
    CreateThread(PositioningThread)
    
    QBCore.Functions.Notify('Use mouse to position, left click to place', 'primary', 5000)
    
    if Config.Debug then
        print('^2[eskdrop-spade]^7 Started placement system for ' .. stashType)
    end
end

-- Create the transparent preview prop
function CreatePreviewProp()
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    
    local propModel = GetHashKey(PlacementData.stashConfig.prop)
    RequestModel(propModel)
    while not HasModelLoaded(propModel) do
        Wait(100)
    end
    
    -- Create prop at player position initially
    PlacementData.previewProp = CreateObject(propModel, coords.x, coords.y, coords.z, false, false, false)
    SetEntityAlpha(PlacementData.previewProp, 150, false) -- Make semi-transparent
    SetEntityCollision(PlacementData.previewProp, false, false) -- Disable collision
    FreezeEntityPosition(PlacementData.previewProp, true)
    
    -- Set model as no longer needed
    SetModelAsNoLongerNeeded(propModel)
    
    if Config.Debug then
        print('^2[eskdrop-spade]^7 Created preview prop for placement')
    end
end

-- Main positioning thread
function PositioningThread()
    while PlacementData.active and PlacementData.phase == 'positioning' do
        Wait(0)
        
        -- Raycast from camera to ground
        local hit, hitCoords = RayCastGamePlayCamera(50.0)
        
        if hit and PlacementData.previewProp then
            -- Update preview prop position
            SetEntityCoords(PlacementData.previewProp, hitCoords.x, hitCoords.y, hitCoords.z, false, false, false, false)
            PlaceObjectOnGroundProperly(PlacementData.previewProp)
            SetEntityHeading(PlacementData.previewProp, PlacementData.heading)
            
            -- Draw green marker at placement location
            DrawMarker(28, hitCoords.x, hitCoords.y, hitCoords.z + 1.0, 0, 0, 0, 0, 0, 0, 0.5, 0.5, 0.5, 0, 255, 0, 100, false, true, 2, nil, nil, false)
        end
        
        -- Handle left click to place
        if IsControlJustPressed(0, 24) then -- Left mouse click
            if hit then
                PlacementData.finalCoords = vector4(hitCoords.x, hitCoords.y, hitCoords.z, PlacementData.heading)
                StartHeadingAdjustment()
            end
        end
        
        -- Handle right click or backspace to cancel
        if IsControlJustPressed(0, 25) or IsControlJustPressed(0, 177) then -- Right click or Backspace
            CancelPlacement()
            break
        end
    end
end

-- Start heading adjustment phase
function StartHeadingAdjustment()
    PlacementData.phase = 'heading'
    
    -- Disable NUI focus
    SetNuiFocus(false, false)
    
    -- Disable player movement controls
    DisablePlayerMovement(true)
    
    -- Start heading adjustment thread
    CreateThread(HeadingAdjustmentThread)
    
    QBCore.Functions.Notify('Use A/D to adjust heading, left click to confirm', 'primary', 5000)
    
    if Config.Debug then
        print('^2[eskdrop-spade]^7 Started heading adjustment phase')
    end
end

-- Heading adjustment thread
function HeadingAdjustmentThread()
    while PlacementData.active and PlacementData.phase == 'heading' do
        Wait(0)
        
        -- Handle A/D keys for heading adjustment
        if IsControlPressed(0, 34) then -- A key (left)
            PlacementData.heading = PlacementData.heading - 1.0
            if PlacementData.heading < 0.0 then
                PlacementData.heading = PlacementData.heading + 360.0
            end
        elseif IsControlPressed(0, 35) then -- D key (right)
            PlacementData.heading = PlacementData.heading + 1.0
            if PlacementData.heading >= 360.0 then
                PlacementData.heading = PlacementData.heading - 360.0
            end
        end
        
        -- Update preview prop heading
        if PlacementData.previewProp then
            SetEntityHeading(PlacementData.previewProp, PlacementData.heading)
        end
        
        -- Update final coordinates with new heading
        if PlacementData.finalCoords then
            PlacementData.finalCoords = vector4(PlacementData.finalCoords.x, PlacementData.finalCoords.y, PlacementData.finalCoords.z, PlacementData.heading)
        end
        
        -- Handle left click to confirm
        if IsControlJustPressed(0, 24) then -- Left mouse click
            ConfirmPlacement()
            break
        end
        
        -- Handle right click or backspace to go back to positioning
        if IsControlJustPressed(0, 25) or IsControlJustPressed(0, 177) then -- Right click or Backspace
            GoBackToPositioning()
            break
        end
    end
end

-- Confirm placement and enter waiting phase
function ConfirmPlacement()
    PlacementData.phase = 'waiting_build'
    
    -- Re-enable player movement
    DisablePlayerMovement(false)
    
    -- Store the placed stash data
    local placementId = 'placement_' .. GetGameTimer()
    placedStashes[placementId] = {
        coords = PlacementData.finalCoords,
        stashType = PlacementData.stashType,
        stashConfig = PlacementData.stashConfig,
        previewProp = PlacementData.previewProp,
        isShowingPrompt = false,
        wasNear = false
    }
    
    -- Start the build interaction thread
    CreateThread(function()
        BuildInteractionThread(placementId)
    end)
    
    QBCore.Functions.Notify('Placement confirmed! Go to the location and press E to build', 'success', 5000)
    
    -- Reset placement data but keep prop for building phase
    PlacementData.active = false
    PlacementData.phase = 'none'
    PlacementData.previewProp = nil -- Don't delete here, it's now managed by placedStashes
    
    if Config.Debug then
        print('^2[eskdrop-spade]^7 Placement confirmed, waiting for build')
    end
end

-- Go back to positioning phase
function GoBackToPositioning()
    PlacementData.phase = 'positioning'
    PlacementData.heading = PlacementData.originalHeading
    
    -- Re-enable player movement and NUI focus
    DisablePlayerMovement(false)
    SetNuiFocus(true, false)
    
    -- Restart positioning thread
    CreateThread(PositioningThread)
    
    QBCore.Functions.Notify('Back to positioning mode', 'primary')
    
    if Config.Debug then
        print('^2[eskdrop-spade]^7 Returned to positioning phase')
    end
end

-- Cancel placement entirely
function CancelPlacement()
    -- Clean up preview prop
    if PlacementData.previewProp then
        DeleteEntity(PlacementData.previewProp)
    end
    
    -- Reset all data
    PlacementData.active = false
    PlacementData.phase = 'none'
    PlacementData.stashType = nil
    PlacementData.stashConfig = nil
    PlacementData.previewProp = nil
    PlacementData.finalCoords = nil
    
    -- Re-enable player movement and disable NUI focus
    DisablePlayerMovement(false)
    SetNuiFocus(false, false)
    
    QBCore.Functions.Notify('Placement cancelled', 'error')
    
    if Config.Debug then
        print('^2[eskdrop-spade]^7 Placement cancelled')
    end
end

-- Build interaction thread for placed stashes
function BuildInteractionThread(placementId)
    local placementData = placedStashes[placementId]
    if not placementData then return end
    
    local coords = placementData.coords
    local stashType = placementData.stashType
    local stashConfig = placementData.stashConfig
    
    while placedStashes[placementId] do
        Wait(100) -- Check more frequently for better responsiveness
        
        local playerCoords = GetEntityCoords(PlayerPedId())
        local distance = #(playerCoords - vector3(coords.x, coords.y, coords.z))
        local isNear = distance < Config.Text3D.distance
        
        -- Only update UI when near/far state changes
        if isNear and not placementData.wasNear then
            -- Player just entered range - start continuous rendering thread
            placementData.isShowingPrompt = true
            placementData.wasNear = true
            
            -- Start continuous text rendering thread like client.lua does
            CreateThread(function()
                StartBuildPromptRendering(placementId, coords)
            end)
            
            if Config.Debug then
                print('^2[eskdrop-spade]^7 Starting build prompt rendering for ' .. placementId)
            end
            
        elseif not isNear and placementData.wasNear then
            -- Player just left range - hide prompt
            HideBuildPrompt(placementId)
            placementData.isShowingPrompt = false
            placementData.wasNear = false
            
            if Config.Debug then
                print('^2[eskdrop-spade]^7 Stopping build prompt rendering for ' .. placementId)
            end
        end
        
        -- Check for E key press only when near and prompt is showing
        if isNear and placementData.isShowingPrompt then
            -- Add debug info every 5 seconds to show E key detection is active
            if Config.Debug and GetGameTimer() % 5000 < 100 then
                print('^5[eskdrop-spade]^7 E key detection active for ' .. placementId .. ' (distance: ' .. string.format("%.2f", distance) .. ')')
            end
            
            if IsControlJustPressed(0, 38) then -- E key
                if Config.Debug then
                    print('^2[eskdrop-spade]^7 E key pressed! Starting build animation for ' .. placementId)
                end
                
                -- Hide prompt immediately to prevent multiple builds
                HideBuildPrompt(placementId)
                placementData.isShowingPrompt = false
                StartBuildAnimation(placementId)
                break
            end
        end
    end
end

-- Start continuous build prompt rendering (like client.lua does for stashes)
function StartBuildPromptRendering(placementId, coords)
    local textCoords = vector3(coords.x, coords.y, coords.z + Config.Text3D.height_offset)
    
    -- Show initial prompt
    ShowBuildPrompt(placementId, textCoords)
    
    -- Continuous rendering loop like client.lua
    while placedStashes[placementId] and placedStashes[placementId].isShowingPrompt do
        local playerCoords = GetEntityCoords(PlayerPedId())
        local distance = #(playerCoords - vector3(coords.x, coords.y, coords.z))
        
        if distance < Config.Text3D.distance then
            -- Update NUI text position continuously
            UpdateBuildPrompt(placementId, textCoords)
            Wait(Config.Text3D.nui_update_frequency or 50)
        else
            break
        end
    end
    
    -- Hide prompt when done
    HideBuildPrompt(placementId)
    
    if Config.Debug then
        print('^6[eskdrop-spade]^7 Stopped build prompt rendering for ' .. placementId)
    end
end

-- Show build prompt using existing NUI system
function ShowBuildPrompt(placementId, coords)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    
    if onScreen then
        SendNUIMessage({
            action = 'show',
            id = 'build_' .. placementId,
            text = 'Press E to build',
            x = x * 1920,
            y = y * 1080
        })
        
        if Config.Debug then
            print('^6[eskdrop-spade]^7 Sent NUI show message for build prompt: build_' .. placementId)
        end
    end
end

-- Update build prompt position (like UpdateNUIText in client.lua)
function UpdateBuildPrompt(placementId, coords)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if onScreen then
        SendNUIMessage({
            action = 'update',
            id = 'build_' .. placementId,
            x = x * 1920,
            y = y * 1080
        })
    end
end

-- Hide build prompt
function HideBuildPrompt(placementId)
    SendNUIMessage({
        action = 'hide',
        id = 'build_' .. placementId
    })
    
    if Config.Debug then
        print('^6[eskdrop-spade]^7 Sent NUI hide message for build prompt: build_' .. placementId)
    end
end

-- Start build animation and create actual stash
function StartBuildAnimation(placementId)
    if Config.Debug then
        print('^2[eskdrop-spade]^7 StartBuildAnimation called for ' .. placementId)
    end
    
    local placementData = placedStashes[placementId]
    if not placementData then 
        if Config.Debug then
            print('^1[eskdrop-spade]^7 Error: Placement data not found for ' .. placementId)
        end
        return 
    end
    
    local coords = placementData.coords
    local stashType = placementData.stashType
    local stashConfig = placementData.stashConfig
    local previewProp = placementData.previewProp
    
    -- Immediately hide build prompt and clean up state
    HideBuildPrompt(placementId)
    placementData.isShowingPrompt = false
    placementData.wasNear = false
    
    if Config.Debug then
        print('^2[eskdrop-spade]^7 Starting build animation process...')
        print('^2[eskdrop-spade]^7 Stash type: ' .. stashType .. ', Animation dict: ' .. stashConfig.animation.dict)
    end
    
    local playerPed = PlayerPedId()
    
    -- Disable player controls during animation
    SetPlayerControl(PlayerId(), false, 0)
    
    -- Load animation dictionary
    RequestAnimDict(stashConfig.animation.dict)
    while not HasAnimDictLoaded(stashConfig.animation.dict) do
        Wait(100)
        if Config.Debug then
            print('^3[eskdrop-spade]^7 Waiting for animation dictionary to load: ' .. stashConfig.animation.dict)
        end
    end
    
    if Config.Debug then
        print('^2[eskdrop-spade]^7 Animation dictionary loaded, starting animation')
    end
    
    -- Play animation
    TaskPlayAnim(playerPed, stashConfig.animation.dict, stashConfig.animation.name, 8.0, -8.0, stashConfig.animation.duration, 1, 0, false, false, false)
    
    -- Show notification
    QBCore.Functions.Notify('Building ' .. stashConfig.label .. '...', 'primary', stashConfig.animation.duration)
    
    if Config.Debug then
        print('^2[eskdrop-spade]^7 Animation started, waiting ' .. stashConfig.animation.duration .. 'ms')
    end
    
    -- Wait for animation to complete
    Wait(stashConfig.animation.duration)
    
    -- Clear animation and restore controls
    ClearPedTasks(playerPed)
    SetPlayerControl(PlayerId(), true, 1)
    
    if Config.Debug then
        print('^2[eskdrop-spade]^7 Animation completed, clearing preview prop and creating final prop')
    end
    
    -- Delete preview prop
    if previewProp and DoesEntityExist(previewProp) then
        DeleteEntity(previewProp)
        if Config.Debug then
            print('^2[eskdrop-spade]^7 Preview prop deleted')
        end
    end
    
    -- Create the actual stash prop
    local propModel = GetHashKey(stashConfig.prop)
    RequestModel(propModel)
    while not HasModelLoaded(propModel) do
        Wait(100)
        if Config.Debug then
            print('^3[eskdrop-spade]^7 Waiting for final prop model to load: ' .. stashConfig.prop)
        end
    end
    
    if Config.Debug then
        print('^2[eskdrop-spade]^7 Creating final prop at coords: ' .. coords.x .. ', ' .. coords.y .. ', ' .. coords.z .. ' with heading: ' .. coords.w)
    end
    
    local prop = CreateObject(propModel, coords.x, coords.y, coords.z, true, true, true)
    PlaceObjectOnGroundProperly(prop)
    SetEntityHeading(prop, coords.w)
    SetEntityAsMissionEntity(prop, true, true)
    FreezeEntityPosition(prop, true)
    SetEntityAlpha(prop, 255, false) -- Make fully opaque
    
    -- Set model as no longer needed
    SetModelAsNoLongerNeeded(propModel)
    
    if Config.Debug then
        print('^2[eskdrop-spade]^7 Final prop created, triggering server event')
    end
    
    -- Request player name from server (this will create the stash and store the prop handle)
    TriggerServerEvent('eskdrop-spade:client:getPlayerName', coords, prop, stashType)
    
    -- Clean up placement data completely
    if placedStashes[placementId] then
        -- Ensure build prompt is hidden
        HideBuildPrompt(placementId)
        -- Remove from placed stashes
        placedStashes[placementId] = nil
    end
    
    if Config.Debug then
        print('^2[eskdrop-spade]^7 Built ' .. stashType .. ' stash at placement location')
    end
end

-- Utility function for raycasting
function RayCastGamePlayCamera(distance)
    local cameraRotation = GetGameplayCamRot()
    local cameraCoord = GetGameplayCamCoord()
    local direction = RotationToDirection(cameraRotation)
    local destination = vector3(cameraCoord.x + direction.x * distance, cameraCoord.y + direction.y * distance, cameraCoord.z + direction.z * distance)
    local rayHandle = StartShapeTestRay(cameraCoord.x, cameraCoord.y, cameraCoord.z, destination.x, destination.y, destination.z, -1, PlayerPedId(), 0)
    local _, hit, endCoords, _, _ = GetShapeTestResult(rayHandle)
    return hit, endCoords
end

-- Convert rotation to direction
function RotationToDirection(rotation)
    local adjustedRotation = vector3((math.pi / 180) * rotation.x, (math.pi / 180) * rotation.y, (math.pi / 180) * rotation.z)
    local direction = vector3(-math.sin(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)), math.cos(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)), math.sin(adjustedRotation.x))
    return direction
end

-- Disable/enable player movement
function DisablePlayerMovement(disable)
    if disable then
        DisableControlAction(0, 30, true) -- Move Left/Right
        DisableControlAction(0, 31, true) -- Move Up/Down
        DisableControlAction(0, 21, true) -- Sprint
        DisableControlAction(0, 22, true) -- Jump
        DisableControlAction(0, 36, true) -- Ctrl (Duck)
    end
end

-- Export the main function
exports('StartPlacementSystem', StartPlacementSystem)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        -- Clean up any active placement
        if PlacementData.active then
            CancelPlacement()
        end
        
        -- Clean up all placed but not built stashes
        for placementId, data in pairs(placedStashes) do
            if data.previewProp and DoesEntityExist(data.previewProp) then
                DeleteEntity(data.previewProp)
            end
            -- Hide any build prompts that might be showing
            HideBuildPrompt(placementId)
            if Config.Debug then
                print('^3[eskdrop-spade]^7 Cleaned up placement: ' .. placementId)
            end
        end
        placedStashes = {}
        
        -- Clear all NUI elements related to placement
        SendNUIMessage({action = 'clear'})
    end
end)
