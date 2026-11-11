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
}

function lock:ConstructUI(entry, props, state)
	local ui, header, footer = self:ConstructUITemplate(entry, props or self.Properties, state or self.State)
	header()

	footer()
end

function lock:PreEvaluate()
	self:CaptureLockPose()
end

-- FIXME: This doesn't lock scales!
function lock:Evaluate(entity, controlledBone, transforms, indices, locals, parents)
	self:ApplyLock(entity, controlledBone, transforms, indices, locals, parents, "scale")
end

function lock:PostEvaluate()
	self._snapshot = nil
end

local function createConstraint(state, name)
	local base = lock:Init(state, name)
	---@cast base ScaleLockConstraint
	return base
end

return createConstraint
