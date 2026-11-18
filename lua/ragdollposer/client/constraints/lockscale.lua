-- Vibecoded the scale locks with GPT-6 Luna

---@class ScaleLockConstraint: Constraint
local lock = include("base.lua")

lock.Properties = {
	type = "lockscale",
	category = "#tool.ragdollposer.constraint.category.transform",
	name = "#tool.ragdollposer.constraint.lockscale.name",
	desc = "#tool.ragdollposer.constraint.lockscale.desc",
	help = "#tool.ragdollposer.constraint.lockscale.help",
	icon = "icon16/arrow_out.png",
	short = "#tool.ragdollposer.constraint.lockscale.short",
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

-- FIXME: This doesn't lock scales!
function lock:Evaluate(entity, controlledBone, transforms, locals, parents, output)
	self._postEvaluateBone = self:ApplyLock(entity, controlledBone, "scale", output) and self.State.bone
end

function lock:PostEvaluate(entity, controlledBone, locals, parents, output)
	if self._postEvaluateBone then
		self:PostApplyLock(self._postEvaluateBone, locals, parents, output)
	end
	self._postEvaluateBone = nil
end

local function createConstraint(entity, state, name)
	local base = lock:Init(entity, state, name)
	---@cast base ScaleLockConstraint
	return base
end

if RagdollPoser.Constraints and not RagdollPoser.Constraints:IsRefreshing() then
	hook.Run("RagdollPoser_Constraints_Refresh", lock.Properties.type)
end

return createConstraint
