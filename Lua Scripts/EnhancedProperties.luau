--[[
    EnhancedProperty - A module for managing any property on any instance with modifiers and smooth transitions.
    
    Usage Example:
        local EnhancedProperty = require(path.to.EnhancedProperty)
        local Modifier = EnhancedProperty.Modifier
        
        -- Create an enhanced property instance (cached - multiple scripts get the same instance)
        local camera = workspace.CurrentCamera
        local enhancedFOV = EnhancedProperty.new(camera, "FieldOfView")
        
        -- Initialize the PreRender loop (only needs to be called once per instance+property)
        enhancedFOV:init()
        
        -- Create a modifier for zooming in
        local zoomModifier = Modifier.new("ZoomIn")
        zoomModifier:setOperation("multiply")
        zoomModifier:setValue(0.8) -- 80% FOV (zoomed in)
        zoomModifier:setPriority(1)
        zoomModifier:setBeginAnimationLength(0.5)
        zoomModifier:setEndAnimationLength(0.3)
        
        -- Add the modifier
        enhancedFOV:addModifier(zoomModifier)
        
        -- Enable/disable the modifier
        zoomModifier:enable()  -- Smoothly fades in over 0.5 seconds
        -- ... later ...
        zoomModifier:disable() -- Smoothly fades out over 0.3 seconds
        
        -- The property updates automatically via PreRender after init() is called
        -- Or apply immediately without fading
        enhancedFOV:applyModifiers()
        
        -- Example with other properties:
        local part = workspace.Part
        local enhancedTransparency = EnhancedProperty.new(part, "Transparency")
        enhancedTransparency:init()
        
        local fadeModifier = Modifier.new("FadeOut")
        fadeModifier:setOperation("add")
        fadeModifier:setValue(0.5)
        enhancedTransparency:addModifier(fadeModifier)
        fadeModifier:enable()
        
    Note: Multiple scripts can call EnhancedProperty.new() on the same instance+property and they will
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

-- Cache for property instances (key: instance:propertyName)
local propertyCache = {}

function module.new(instance, propertyName)
	-- Validate inputs
	if not instance then
		error("EnhancedProperty.new: instance is required", 2)
	end
	if not propertyName or type(propertyName) ~= "string" then
		error("EnhancedProperty.new: propertyName must be a string", 2)
	end

	-- Check if property exists
	if not pcall(function() return instance[propertyName] end) then
		error(("EnhancedProperty.new: property '%s' does not exist on instance"):format(tostring(propertyName)), 2)
	end

	-- Create cache key
	local cacheKey = tostring(instance) .. ":" .. propertyName

	-- Check if we already have an instance for this instance+property
	if propertyCache[cacheKey] then
		return propertyCache[cacheKey]
	end

	-- Get base value
	local baseValue = instance[propertyName]
	if type(baseValue) ~= "number" then
		error(("EnhancedProperty.new: property '%s' must be a number (got %s)"):format(tostring(propertyName), typeof(baseValue)), 2)
	end

	-- Create new instance
	local self = setmetatable({}, module)
	self.instance = instance
	self.propertyName = propertyName
	self.baseValue = baseValue
	self.modifiers = {}
	self.initsignal = nil

	-- Cache the instance
	propertyCache[cacheKey] = self

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
	Refreshes the base value from the instance property.
	Useful if the property was changed externally and you want to reset the base.
]]
function module:refreshBaseValue()
	self.baseValue = self.instance[self.propertyName]
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
	self.enabled = false
	self.operation = "add"
	self.value = 0
	self.fadeinTime = 1 -- Begin animation length (default: 1)
	self.fadeoutTime = 1 -- End animation length (default: 1)
	self.floatCurve = nil
	self.toggledSince = -9999
	self.startProgress = 0 -- Progress when toggle started (0-1)
	return self
end

-- Helper function to get current visual progress
local function getCurrentProgress(modifier)
	local now = os.clock()
	local fadeDuration = modifier.enabled and (modifier.fadeinTime or 1) or (modifier.fadeoutTime or 1)
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
function modifierClass:setOperation(operation: ("add" | "multiply") | ((currentValue: number, modifierValue: number) -> number))
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
function modifierClass:setBeginAnimationLength(time: number)
	self.fadeinTime = time
end
function modifierClass:setEndAnimationLength(time: number)
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
	local currentValue = self.baseValue
	for _, modifier in self.modifiers do
		if modifier.enabled then
			if typeof(modifier.operation) == "function" then
				currentValue = modifier.operation(currentValue, modifier.value)
			elseif modifier.operation == "add" then
				currentValue += modifier.value
			elseif modifier.operation == "multiply" then
				currentValue *= modifier.value
			end
		end
	end
	self.instance[self.propertyName] = currentValue
end

function module:update()
	local currentValue = self.baseValue
	for _, modifier in self.modifiers do
		-- Calculate fade progress based on toggledSince and fade times
		local fadeDuration = modifier.enabled and (modifier.fadeinTime or 1) or (modifier.fadeoutTime or 1)
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
				currentValue = modifier.operation(currentValue, (modifier.value or 0) * fadeProgress)
			elseif modifier.operation == "add" then
				currentValue += (modifier.value or 0) * fadeProgress
			elseif modifier.operation == "multiply" then
				-- For multiply, interpolate between 1 (no effect) and modifier.value (full effect)
				currentValue *= (1 + ((modifier.value or 1) - 1) * fadeProgress)
			end
		end
	end

	self.instance[self.propertyName] = currentValue
end

-- Export modifierClass so users can create modifiers
module.Modifier = modifierClass

-- Export preset curves for convenience
module.PresetCurves = presetCurves

return module
