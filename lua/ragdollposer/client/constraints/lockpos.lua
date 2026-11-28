-- Vibecoded the rotation locks with GPT-6 Luna

---@class PositionLockConstraint: Constraint
local lock = include("base.lua")

lock.Properties = {
	type = "lockpos",
	category = "#tool.ragdollposer.constraint.category.transform",
	name = "#tool.ragdollposer.constraint.lockpos.name",
	desc = "#tool.ragdollposer.constraint.lockpos.desc",
	help = "#tool.ragdollposer.constraint.lockpos.help",
	icon = "icon16/arrow_right.png",
	short = "#tool.ragdollposer.constraint.lockpos.short",
}

local spriteMat = Material(lock.Properties.icon)
function lock:Draw()
	self:DrawIcon(self.State.target, self.State.bone, spriteMat)
end

function lock:ConstructUI(entry, props, state)
	local ui, header, footer = self:ConstructUITemplate(entry, props or self.Properties, state or self.State)
	header()

	footer()
end

function lock:PreEvaluate()
	return self:CaptureLockPose()
end

function lock:Evaluate(entity, controlledBone, transforms, locals, parents, output)
	self._postEvaluateBone = self:ApplyLock(entity, controlledBone, "position", output) and self.State.bone
end

function lock:PostEvaluate(entity, controlledBone, locals, parents, output)
	if self._postEvaluateBone then
		self:PostApplyLock(self._postEvaluateBone, locals, parents, output)
	end
	self._postEvaluateBone = nil
end

local function createConstraint(entity, state, name)
	local base = lock:Init(entity, state, name)
	---@cast base PositionLockConstraint
	base:ValidateBoneName()

	return base
end

if RagdollPoser.Constraints and not RagdollPoser.Constraints:IsRefreshing() then
	hook.Run("RagdollPoser_Constraints_Refresh", lock.Properties.type)
end

return createConstraint
