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
	short = "#tool.ragdollposer.constraint.lockang.short",
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
	self._postEvaluateBone = self:ApplyLock(entity, controlledBone, "rotation", output) and self.State.bone
end

function lock:PostEvaluate(entity, controlledBone, locals, parents, output)
	if self._postEvaluateBone then
		self:PostApplyLock(self._postEvaluateBone, locals, parents, output)
	end
	self._postEvaluateBone = nil
end

local function createConstraint(entity, state, name)
	local base = lock:Init(entity, state, name)
	---@cast base RotationLockConstraint
	return base
end

if RagdollPoser.Constraints and not RagdollPoser.Constraints:IsRefreshing() then
	hook.Run("RagdollPoser_Constraints_Refresh", lock.Properties.type)
end

return createConstraint
