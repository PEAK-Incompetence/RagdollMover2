-- Vibecoded the rotation locks with GPT-6 Luna

---@class PositionLockConstraint: Constraint
local lock = include("base.lua")

lock.Properties = {
	type = "lockpos",
	category = "#tool.ragdollposer.constraint.category.transform",
	name = "#tool.ragdollposer.constraint.lockpos.name",
	desc = "#tool.ragdollposer.constraint.lockpos.desc",
	help = "#tool.ragdollposer.constraint.lockpos.help",
	icon = "",
}

function lock:ConstructUI(entry, props, state)
	local ui, header, footer = self:ConstructUITemplate(entry, props or self.Properties, state or self.State)
	header()

	footer()
end

function lock:PreEvaluate()
	self:CaptureLockPose()
end

function lock:Evaluate(entity, controlledBone, transforms, indices, locals, parents)
	self:ApplyLock(entity, controlledBone, transforms, indices, locals, parents, "position")
end

function lock:PostEvaluate()
	self._snapshot = nil
end

local function createConstraint(state, name)
	local base = lock:Init(state, name)
	---@cast base PositionLockConstraint
	return base
end

return createConstraint
