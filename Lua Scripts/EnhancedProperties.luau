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

-- Signal class for simple custom events

local Signal = {}
Signal.__index = Signal

function Signal.new()
    local self = setmetatable({}, Signal)
    self._connections = {}
    return self
end

function Signal:Connect(callback)
    assert(type(callback) == "function", "Callback must be a function")
    local connection = {}
    connection.Connected = true
    function connection:Disconnect()
        if connection.Connected then
            connection.Connected = false
            for i, conn in ipairs(self._connections) do
                if conn == connection then
                    table.remove(self._connections, i)
                    break
                end
            end
        end
    end
    table.insert(self._connections, connection)
    connection._callback = callback
    connection._signal = self
    return connection
end

function Signal:Fire(...)
    for _, connection in ipairs(self._connections) do
        if connection.Connected then
            task.spawn(connection._callback, ...)
        end
    end
end

function Signal:DisconnectAll()
    for _, connection in ipairs(self._connections) do
        connection.Connected = false
    end
    self._connections = {}
end

-- Signal metatable for syntax consistency
Signal.Connect = Signal.Connect
Signal.Fire = Signal.Fire
Signal.DisconnectAll = Signal.DisconnectAll

-- Expose Signal class
local EnhancedSignal = Signal


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
	self._cacheKey = cacheKey -- Store cache key for cleanup
	self._destroyed = false
	
	-- Auto-destroy when instance is removed (even if init() wasn't called)
	self._ancestryConnection = instance.AncestryChanged:Connect(function()
		if not instance.Parent then
			-- Instance was removed from the game tree
			self:destroy()
		end
	end)

	-- Cache the instance
	propertyCache[cacheKey] = self

	return self
end

function module:init()
	if self._destroyed then
		warn("Cannot init destroyed EnhancedProperty instance")
		return self
	end
	
	-- Disconnect existing signal if it exists
	if self.initsignal then
		self.initsignal:Disconnect()
		self.initsignal = nil
	end

	-- Create new PreRender connection
	self.initsignal = RunService.PreRender:Connect(function()
		self:update()
	end)

	return self, self.initsignal
end

--[[
	Refreshes the base value from the instance property.
	Useful if the property was changed externally and you want to reset the base.
]]
function module:refreshBaseValue()
	if self._destroyed or not self.instance then
		warn("Cannot refresh base value on destroyed EnhancedProperty instance")
		return self
	end
	self.baseValue = self.instance[self.propertyName]
	return self
end

--[[
	Destroys the EnhancedProperty instance, cleaning up all resources.
	Disconnects the update loop, removes from cache, and destroys all modifiers.
]]
function module:destroy()
	if self._destroyed then
		return
	end
	
	self._destroyed = true
	
	-- Disconnect update signal
	if self.initsignal then
		self.initsignal:Disconnect()
		self.initsignal = nil
	end
	
	-- Disconnect ancestry connection
	if self._ancestryConnection then
		self._ancestryConnection:Disconnect()
		self._ancestryConnection = nil
	end
	
	-- Destroy all modifiers
	for _, modifier in self.modifiers do
		modifier:destroy()
	end
	self.modifiers = {}
	
	-- Remove from cache
	if self._cacheKey and propertyCache[self._cacheKey] == self then
		propertyCache[self._cacheKey] = nil
	end
	
	-- Clear references
	self.instance = nil
	self.propertyName = nil
	self.baseValue = nil
	self._cacheKey = nil
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
	
	-- Signals
	self.Began = Signal.new()
	self.Ended = Signal.new()
	self.FadedIn = Signal.new()
	self.FadedOut = Signal.new()
	
	-- Track fade completion state
	self._hasFadedIn = false
	self._hasFadedOut = false
	
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
		
		-- Reset fade completion flags
		self._hasFadedIn = false
		self._hasFadedOut = false
		
		-- Fire Began signal
		self.Began:Fire()
	end
	return self
end
function modifierClass:disable()
	if self.enabled then
		-- Get the current visual progress before switching
		self.startProgress = getCurrentProgress(self)

		self.enabled = false
		self.toggledSince = os.clock()
		
		-- Reset fade completion flags
		self._hasFadedIn = false
		self._hasFadedOut = false
		
		-- Fire Ended signal
		self.Ended:Fire()
	end
	return self
end
function modifierClass:setPriority(priority: number)
	self.priority = priority
	return self
end
function modifierClass:setOperation(operation: ("add" | "multiply") | ((currentValue: number, modifierValue: number) -> number))
	self.operation = operation
	return self
end
function modifierClass:setValue(value: number)
	self.value = value
	return self
end
function modifierClass:setFadeInTime(time: number)
	self.fadeinTime = time
	return self
end
function modifierClass:setFadeOutTime(time: number)
	self.fadeoutTime = time
	return self
end
function modifierClass:setBeginAnimationLength(time: number)
	self.fadeinTime = time
	return self
end
function modifierClass:setEndAnimationLength(time: number)
	self.fadeoutTime = time
	return self
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
	return self
end

--[[
	Destroys the modifier, cleaning up all resources.
	Disconnects all signals and clears references.
]]
function modifierClass:destroy()
	if self._destroyed then
		return
	end
	
	self._destroyed = true
	
	-- Disconnect all signals
	if self.Began then
		self.Began:DisconnectAll()
		self.Began = nil
	end
	if self.Ended then
		self.Ended:DisconnectAll()
		self.Ended = nil
	end
	if self.FadedIn then
		self.FadedIn:DisconnectAll()
		self.FadedIn = nil
	end
	if self.FadedOut then
		self.FadedOut:DisconnectAll()
		self.FadedOut = nil
	end
	
	-- Clear references
	self.floatCurve = nil
	self.operation = nil
	self.name = nil
end

local function __sortModifiers(a, b)
	return a.priority > b.priority
end

function module:addModifier(modifier)
	if self._destroyed then
		warn("Cannot add modifier to destroyed EnhancedProperty instance")
		return self
	end
	if modifier._destroyed then
		warn("Cannot add destroyed modifier")
		return self
	end
	table.insert(self.modifiers, modifier)
	table.sort(self.modifiers, __sortModifiers)
	return self
end

function module:removeModifier(modifier)
	if self._destroyed then
		return self
	end
	for i = #self.modifiers, 1, -1 do
		if self.modifiers[i] == modifier then
			table.remove(self.modifiers, i)
			break
		end
	end
	return self
end

--[[
    Applies modifiers immediately without fading.
    Use update() for smooth fading transitions.
]]
function module:applyModifiers()
	if self._destroyed then
		return self
	end
	
	local currentValue = self.baseValue
	for _, modifier in self.modifiers do
		if modifier.enabled and not modifier._destroyed then
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
	return self
end

function module:update()
	if self._destroyed or not self.instance or not self.instance.Parent then
		-- Instance was destroyed or removed, clean up
		if not self._destroyed then
			self:destroy()
		end
		return
	end
	
	local currentValue = self.baseValue
	for _, modifier in self.modifiers do
		-- Skip destroyed modifiers
		if modifier._destroyed then
			-- Skip to next modifier
		else
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
						-- Fire FadedIn signal when fade-in completes
						if not modifier._hasFadedIn then
							modifier._hasFadedIn = true
							modifier.FadedIn:Fire()
						end
					end
				else
					-- Fading out: interpolate from startProgress to 0
					if diff < fadeDuration then
						local fadeAmount = diff / fadeDuration
						rawProgress = startProgress * (1 - fadeAmount)
					else
						rawProgress = 0
						-- Fire FadedOut signal when fade-out completes
						if not modifier._hasFadedOut then
							modifier._hasFadedOut = true
							modifier.FadedOut:Fire()
						end
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
			
			-- Check for fade completion after FloatCurve is applied (for edge cases)
			if modifier.enabled and fadeProgress >= 1 and not modifier._hasFadedIn then
				modifier._hasFadedIn = true
				modifier.FadedIn:Fire()
			elseif not modifier.enabled and fadeProgress <= 0 and not modifier._hasFadedOut then
				modifier._hasFadedOut = true
				modifier.FadedOut:Fire()
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
	end

	self.instance[self.propertyName] = currentValue
end

-- Export modifierClass so users can create modifiers
module.Modifier = modifierClass

-- Export preset curves for convenience
module.PresetCurves = presetCurves

return module
