-- Vibecoded the rotation locks with GPT-6 Luna

---@class RotationLockConstraint: Constraint
local lock = include("base.lua")

lock.Properties = {
	type = "lockang",
	category = "#tool.ragdollposer.constraint.category.transform",
	name = "#tool.ragdollposer.constraint.lockang.name",
	desc = "#tool.ragdollposer.constraint.lockang.desc",
	help = "#tool.ragdollposer.constraint.lockang.help",
	icon = "icon16/arrow_rotate_anticlockwise.png",
}

function lock:ConstructUI(entry, props, state)
	local ui, header, footer = self:ConstructUITemplate(entry, props or self.Properties, state or self.State)
	header()

	footer()
end

function lock:PreEvaluate()
	return self:CaptureLockPose()
end

function lock:Evaluate(entity, controlledBone, transforms, locals, parents, output)
	self._postEvaluateBone = self:ApplyLock(entity, controlledBone, "rotation", output)
		and self.State.bone
end

function lock:PostEvaluate(entity, controlledBone, locals, parents, output)
	if self._postEvaluateBone then
		self:PostApplyLock(self._postEvaluateBone, locals, parents, output)
	end
	self._postEvaluateBone = nil
end

local function createConstraint(state, name)
	local base = lock:Init(state, name)
	---@cast base RotationLockConstraint
	return base
end

return createConstraint
