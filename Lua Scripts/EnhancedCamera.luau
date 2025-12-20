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

-- Preset FloatCurve instances
local function createFloatCurve(Type: Enum.KeyInterpolationMode): FloatCurve
	local floatCurve = Instance.new("FloatCurve")

	floatCurve:SetKeys(
		{
			FloatCurveKey.new(0, 0, Type), FloatCurveKey.new(1, 1, Type)
		}
	)

	floatCurve.Parent = script -- Puts it in a safe storage location

	return floatCurve
end

local presetCurves = {}

for _,v in Enum.KeyInterpolationMode:GetEnumItems() do
	presetCurves[v.Name] = createFloatCurve(v)
end

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
    fadeoutTime: number,
    floatCurve: FloatCurve | nil [Used for custom fade curves, nil = linear]
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
	self.floatCurve = nil
	self.toggledSince = os.clock()
	self.startProgress = 1 -- Progress when toggle started (0-1)
	return self
end

-- Helper function to get current visual progress
local function getCurrentProgress(modifier)
	local now = os.clock()
	local fadeDuration = modifier.enabled and (modifier.fadeinTime or 0.3) or (modifier.fadeoutTime or 0.3)
	local diff = now - modifier.toggledSince
	local startProgress = modifier.startProgress or (modifier.enabled and 0 or 1)
	
	if modifier.enabled then
		-- Currently fading in
		if diff < fadeDuration then
			local fadeAmount = diff / fadeDuration
			return startProgress + (1 - startProgress) * fadeAmount
		else
			return 1
		end
	else
		-- Currently fading out
		if diff < fadeDuration then
			local fadeAmount = diff / fadeDuration
			return startProgress * (1 - fadeAmount)
		else
			return 0
		end
	end
end

function modifierClass:enable()
	if not self.enabled then
		-- Get the current visual progress before switching
		self.startProgress = getCurrentProgress(self)
		
		self.enabled = true
		self.toggledSince = os.clock()
	end
end
function modifierClass:disable()
	if self.enabled then
		-- Get the current visual progress before switching
		self.startProgress = getCurrentProgress(self)
		
		self.enabled = false
		self.toggledSince = os.clock()
	end
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
function modifierClass:setFloatCurve(curve: FloatCurve | Enum.KeyInterpolationMode)
	if typeof(curve) == "EnumItem" then
		-- Use preset curve by name or value
		local preset = presetCurves[curve] or presetCurves[curve.Name]
		if preset then
			self.floatCurve = preset
		else
			warn(("Unknown preset curve: %s. Available: %s"):format(
				tostring(curve),
				table.concat((function()
					local names = {}
					for k in pairs(presetCurves) do
						table.insert(names, k)
					end
					return names
				end)(), ", ")
				))
			self.floatCurve = nil
		end
	elseif typeof(curve) == "Instance" and curve:IsA("FloatCurve") then
		self.floatCurve = curve
	else
		self.floatCurve = nil -- Linear (default)
	end
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
		local rawProgress = modifier.enabled and 1 or 0

		if modifier.toggledSince then
			local diff = now - modifier.toggledSince
			local startProgress = modifier.startProgress or (modifier.enabled and 0 or 1)
			
			if modifier.enabled then
				-- Fading in: interpolate from startProgress to 1
				if diff < fadeDuration then
					local fadeAmount = diff / fadeDuration
					rawProgress = startProgress + (1 - startProgress) * fadeAmount
				else
					rawProgress = 1
				end
			else
				-- Fading out: interpolate from startProgress to 0
				if diff < fadeDuration then
					local fadeAmount = diff / fadeDuration
					rawProgress = startProgress * (1 - fadeAmount)
				else
					rawProgress = 0
				end
			end
		else
			rawProgress = modifier.enabled and 1 or 0
		end

		-- Apply FloatCurve if available
		local fadeProgress = rawProgress
		if modifier.floatCurve then
			fadeProgress = modifier.floatCurve:GetValueAtTime(rawProgress)
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

-- Export preset curves for convenience
module.PresetCurves = presetCurves

return module
