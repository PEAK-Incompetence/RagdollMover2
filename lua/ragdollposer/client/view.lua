--- [CLIENT]
---
---All this returns is eye positions and eye angles, with aim vector support
---
---@class RagdollPoser.View
local MGR = {}

local eyePos, eyeAngles = MainEyePos, MainEyeAngles
local cursorPos = input.GetCursorPos

---@return Vector eyePos main view position
---@return Vector eyeVector cursor (aim) vector
---@return Angle eyeAngles main looking angle
function MGR:GetView()
	local eyepos = eyePos()
	local eyeang = eyeAngles()
	local eyevec = eyeang:Forward()

	if vgui.CursorVisible() then
		eyevec = gui.ScreenToVector(cursorPos())
	end

	return eyepos, eyevec, eyeang
end

---@type TraceResult
local output = {
	HitPos = Vector(),
	StartPos = Vector(),
	Normal = Vector(),
}
---@type Trace
local traceConfig = {
	filter = {},
	start = Vector(),
	endPos = Vector(),
	output = output,
}
---@param filter Entity[]?
function MGR:GetTrace(filter)
	local eyepos, eyevec = self:GetView()

	traceConfig.start = eyepos
	traceConfig.endPos = eyepos + eyevec * 16384
	traceConfig.filter = filter
	util.TraceLine(traceConfig)

	return output
end

RagdollPoser.View = MGR
