--- [CLIENT]
---
---All this returns is eye positions and eye angles, with aim vector support
---
---@class RagdollPoser.View
local MGR = {}

local eyePos, eyeAngles = MainEyePos, MainEyeAngles
local cursorPos = input.GetCursorPos

---@return Vector, Vector, Angle
function MGR:GetView()
	local eyepos = eyePos()
	local eyeang = eyeAngles()
	local eyevec = eyeang:Forward()

	if vgui.CursorVisible() then
		eyevec = gui.ScreenToVector(cursorPos())
	end

	return eyepos, eyevec, eyeang
end

RagdollPoser.View = MGR
