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

function lock:Evaluate()
	-- if the bone that we're moving is precisely the bone we want to move, we should move it
	-- if this bone exists down the chain that we're moving, keep it locked
	-- not only that, that bones children bone should also stay locked (just like old ragdoll mover)
end

local function createConstraint(state, name)
	local base = lock:Init(state, name)
	---@cast base PositionLockConstraint
	return base
end

return createConstraint
