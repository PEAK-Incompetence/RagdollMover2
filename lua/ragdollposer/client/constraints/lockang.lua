---@class RotationLockConstraint: Constraint
local lock = include("base.lua")

lock.Properties = {
	type = "lockang",
	category = "#tool.ragdollposer.constraint.category.transform",
	name = "#tool.ragdollposer.constraint.lockang.name",
	desc = "#tool.ragdollposer.constraint.lockang.desc",
	help = "#tool.ragdollposer.constraint.lockang.help",
	icon = "",
}

function lock:ConstructUI(entry, props, state)
	local ui, header, footer = self:ConstructUITemplate(entry, props or self.Properties, state or self.State)
	header()

	footer()
end

function lock:Evaluate() end

local function createConstraint(state)
	local base = lock:Init(state)
	---@cast base RotationLockConstraint
	return base
end

return createConstraint
