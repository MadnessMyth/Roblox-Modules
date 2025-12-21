local GuiCursor = {}

local rs = game:GetService("RunService")
local uis = game:GetService("UserInputService")

local metafunctions = {
	activate = function(this)
		local this = getmetatable(this)

		return rs.RenderStepped:Connect(function()
			local mouseLocation = uis:GetMouseLocation()

			this:__newindex("Position", UDim2.new(
				this:__index("Offset").X.Scale,
				this:__index("Offset").X.Offset + mouseLocation.X,
				this:__index("Offset").Y.Scale,
				this:__index("Offset").Y.Offset + mouseLocation.Y
				)
			)
		end)
	end,
}

local userService = game:GetService("Players")

function GuiCursor.new()
	if userService.LocalPlayer.PlayerGui:FindFirstChild("GuiCursor") then
		error("There is already a cursor in StarterGui!")
	end

	-- Create a screen gui
	local ScreenGui = Instance.new("ScreenGui")
	local ImageLabel = Instance.new("ImageLabel")

	ScreenGui.ScreenInsets = Enum.ScreenInsets.None
	ScreenGui.Name = "GuiCursor"
	ScreenGui.ResetOnSpawn = false
	ScreenGui.DisplayOrder = 99999
	ScreenGui.Parent = userService.LocalPlayer.PlayerGui

	ImageLabel.Parent = ScreenGui
	ImageLabel.AnchorPoint = Vector2.zero
	ImageLabel.Size = UDim2.fromScale(0.25, 0.25)
	ImageLabel.Name = "Cursor"

	local UserInputService = game:GetService("UserInputService")
	-- Gets the user input service which has a mouse icon enabled property.

	UserInputService.MouseIconEnabled = false
	-- Disables the default mouse

	local Cursor = {}

	Cursor.Offset = UDim2.new()
	Cursor.Filled = false
	Cursor.Roundness = UDim.new()
	Cursor.Squareify = true

	local function updateGuiCursor()		
		-- Fill
		ImageLabel.BackgroundTransparency = Cursor.Filled and 0 or 1

		-- Square
		if Cursor.Squareify then
			if not ImageLabel:FindFirstChildOfClass("UIAspectRatioConstraint") then
				Instance.new("UIAspectRatioConstraint", ImageLabel)
			end
		else
			local x = ImageLabel:FindFirstChildOfClass("UIAspectRatioConstraint")
			if x then x:Destroy() end
		end

		-- Corners

		if Cursor.Roundness.Scale > 0 or Cursor.Roundness.Offset > 0 then
			local UICorner = ImageLabel:FindFirstChildOfClass("UICorner")

			if not UICorner then
				UICorner = Instance.new("UICorner", ImageLabel)
			end

			UICorner.CornerRadius = Cursor.Roundness
		else
			local UICorner = ImageLabel:FindFirstChildOfClass("UICorner")

			if UICorner then
				UICorner:Destroy()
			end
		end
	end

	updateGuiCursor()	

	return setmetatable({}, {
		__index = function(_, index)
			return Cursor[index] or metafunctions[index]
		end,

		__newindex = function(_, index, value)
			if Cursor[index] ~= nil then
				Cursor[index] = value
			else
				ImageLabel[index] = value
			end

			updateGuiCursor()
		end,
	})
end

return GuiCursor