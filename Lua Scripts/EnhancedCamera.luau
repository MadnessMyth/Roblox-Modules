local module = {}
module.__index = module

function module:__new(camera)
    local self = setmetatable({}, module)
    self.camera = camera
    self.basefov = camera.FieldOfView
    self.modifiers = {}
    return self
end

--[[
Modifier will contain {
    priority: number,
    enabled: boolean,
    operation: function or "add" | "multiply",
    value: number,
    fadeinTime: number,
    fadeoutTime: number
    enabledSince: number [Used internally to track the time the modifier was enabled]
    }
]]

local modifierClass = {}
modifierClass.__index = modifierClass
function modifierClass:__new(name)
    local self = setmetatable({}, modifierClass)
    self.name = name
    self.priority = 0
    self.enabled = true
    self.operation = "add"
    self.value = 0
    return self
end

function modifierClass:enable()
    self.enabled = true
    self.enabledSince = os.clock()
end
function modifierClass:disable()
    self.enabled = false
    self.enabledSince = 0
end
function modifierClass:setPriority(priority: number)
    self.priority = priority
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
    if modifier.enabled then
        if modifier.enabledSince then
            local timeSinceEnabled = os.clock() - modifier.enabledSince
            if timeSinceEnabled < modifier.fadeinTime then
                currentFov = modifier.operation(currentFov, modifier.value)
            end
        end
    end
   end
   self.camera.FieldOfView = currentFov
end

return module
