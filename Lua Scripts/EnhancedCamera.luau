--[[
    EnhancedCamera - A module for managing camera Field of View with modifiers and smooth transitions.
    
    Usage Example:
        local EnhancedCamera = require(path.to.EnhancedCamera)
        local Modifier = EnhancedCamera.Modifier
        
        -- Create an enhanced camera instance (cached - multiple scripts get the same instance)
        local camera = workspace.CurrentCamera
        local enhancedCam = EnhancedCamera.new(camera)
        
        -- Initialize the PreRender loop (only needs to be called once per camera)
        enhancedCam:init()
        
        -- Create a modifier for zooming in
        local zoomModifier = Modifier.new("ZoomIn")
        zoomModifier:setOperation("multiply")
        zoomModifier:setValue(0.8) -- 80% FOV (zoomed in)
        zoomModifier:setPriority(1)
        zoomModifier:setFadeInTime(0.5)
        zoomModifier:setFadeOutTime(0.3)
        
        -- Add the modifier
        enhancedCam:addModifier(zoomModifier)
        
        -- Enable/disable the modifier
        zoomModifier:enable()  -- Smoothly fades in over 0.5 seconds
        -- ... later ...
        zoomModifier:disable() -- Smoothly fades out over 0.3 seconds
        
        -- The camera FOV updates automatically via PreRender after init() is called
        -- Or apply immediately without fading
        enhancedCam:applyModifiers()
        
    Note: Multiple scripts can call EnhancedCamera.new() on the same camera and they will
    receive the same cached instance, allowing them to add modifiers independently.
]]

local RunService = game:GetService("RunService")

local module = {}
module.__index = module

-- Cache for camera instances
local cameraCache = {}

function module.new(camera)
    -- Check if we already have an instance for this camera
    if cameraCache[camera] then
        return cameraCache[camera]
    end
    
    -- Create new instance
    local self = setmetatable({}, module)
    self.camera = camera
    self.basefov = camera.FieldOfView
    self.modifiers = {}
    self.initsignal = nil
    
    -- Cache the instance
    cameraCache[camera] = self
    
    return self
end

function module:init()
    -- Disconnect existing signal if it exists
    if self.initsignal then
        self.initsignal:Disconnect()
        self.initsignal = nil
    end
    
    -- Create new PreRender connection
    self.initsignal = RunService.PreRender:Connect(function()
        self:update()
    end)
    
    return self.initsignal
end

--[[
Modifier will contain {
    priority: number,
    enabled: boolean,
    operation: function or "add" | "multiply",
    value: number,
    fadeinTime: number,
    fadeoutTime: number
    toggledSince: number [Used internally to track the time the modifier was enabled]
    }
]]

local modifierClass = {}
modifierClass.__index = modifierClass
function modifierClass.new(name)
    local self = setmetatable({}, modifierClass)
    self.name = name
    self.priority = 0
    self.enabled = true
    self.operation = "add"
    self.value = 0
    self.fadeinTime = 0.3
    self.fadeoutTime = 0.3
    self.toggledSince = os.clock()
    return self
end

function modifierClass:enable()
    self.enabled = true
    self.toggledSince = os.clock()
end
function modifierClass:disable()
    self.enabled = false
    self.toggledSince = os.clock()
end
function modifierClass:setPriority(priority: number)
    self.priority = priority
end
function modifierClass:setOperation(operation: ("add" | "multiply") | ((fov: number, value: number) -> number))
    self.operation = operation
end
function modifierClass:setValue(value: number)
    self.value = value
end
function modifierClass:setFadeInTime(time: number)
    self.fadeinTime = time
end
function modifierClass:setFadeOutTime(time: number)
    self.fadeoutTime = time
end

local function __sortModifiers(a, b)
    return a.priority > b.priority
end

function module:addModifier(modifier)
    table.insert(self.modifiers, modifier)
    table.sort(self.modifiers, __sortModifiers)
end

function module:removeModifier(modifier)
    for i = #self.modifiers, 1, -1 do
        if self.modifiers[i] == modifier then
            table.remove(self.modifiers, i)
            break
        end
    end
end

--[[
    Applies modifiers immediately without fading.
    Use update() for smooth fading transitions.
]]
function module:applyModifiers()
    local fov = self.basefov
    for _, modifier in self.modifiers do
        if modifier.enabled then
            if typeof(modifier.operation) == "function" then
                fov = modifier.operation(fov, modifier.value)
            elseif modifier.operation == "add" then
                fov += modifier.value
            elseif modifier.operation == "multiply" then
                fov *= modifier.value
            end
        end
    end
    self.camera.FieldOfView = fov
end

function module:update()
   local currentFov = self.basefov
   for _, modifier in self.modifiers do
      -- Calculate fade progress based on toggledSince and fade times
      local fadeDuration = modifier.enabled and (modifier.fadeinTime or 0.3) or (modifier.fadeoutTime or 0.3)
      local now = os.clock()
      local fadeProgress = 1

      if modifier.toggledSince then
         local diff = now - modifier.toggledSince
         if modifier.enabled then
            -- Fading in
            if diff < fadeDuration then
               fadeProgress = diff / fadeDuration
            else
               fadeProgress = 1
            end
         else
            -- Fading out
            if diff < fadeDuration then
               fadeProgress = 1 - (diff / fadeDuration)
            else
               fadeProgress = 0
            end
         end
      else
         fadeProgress = modifier.enabled and 1 or 0
      end

      if fadeProgress > 0 then
         if typeof(modifier.operation) == "function" then
            currentFov = modifier.operation(currentFov, (modifier.value or 0) * fadeProgress)
         elseif modifier.operation == "add" then
            currentFov += (modifier.value or 0) * fadeProgress
         elseif modifier.operation == "multiply" then
            -- For multiply, interpolate between 1 (no effect) and modifier.value (full effect)
            currentFov *= (1 + ((modifier.value or 1) - 1) * fadeProgress)
         end
      end
   end

   self.camera.FieldOfView = currentFov
end

-- Export modifierClass so users can create modifiers
module.Modifier = modifierClass

return module
