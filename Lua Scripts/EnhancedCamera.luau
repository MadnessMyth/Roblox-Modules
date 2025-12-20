local module = {}
module.__index = module

function module:__new(camera)
    local self = setmetatable({}, module)
    self.camera = camera
    return self
end

function module:update()
    self.camera:update()
end

return module
