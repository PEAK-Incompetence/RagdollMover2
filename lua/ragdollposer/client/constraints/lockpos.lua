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

function lock:ConstructUI(entry)
	local ui, header, footer = self:ConstructUITemplate(entry, self.Properties)
	header()

	footer()
end

function lock:Evaluate() end

local function createConstraint(state)
	local base = lock:Init(state)
	---@cast base PositionLockConstraint
	return base
end

return createConstraint
