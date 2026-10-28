---@class ScaleLockConstraint: Constraint
local lock = include("base.lua")

lock.Properties = {
	type = "lockscale",
	category = "#tool.ragdollposer.constraint.category.transform",
	name = "#tool.ragdollposer.constraint.lockscale.name",
	desc = "#tool.ragdollposer.constraint.lockscale.desc",
	help = "#tool.ragdollposer.constraint.lockscale.help",
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
	---@cast base ScaleLockConstraint
	return base
end

return createConstraint
