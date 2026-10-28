---@class IKConstraint: Constraint
---@field State IKConstraintState
local ik = include("base.lua")

ik.Properties = {
	type = "ik",
	category = "#tool.ragdollposer.constraint.category.tracking",
	name = "#tool.ragdollposer.constraint.ik.name",
	desc = "#tool.ragdollposer.constraint.ik.desc",
	help = "#tool.ragdollposer.constraint.ik.help",
}

---@class IKConstraintState: ConstraintState
---@field iterations integer
---@field length integer
---@field weightPosition boolean
---@field weightPositionValue number
---@field weightRotation boolean
---@field weightRotationValue number
ik.State = table.Merge(table.Copy(ik.State), {
	iterations = 500,
	length = 3, -- chain length
	weightPosition = true,
	weightPositionValue = 1,
	weightRotation = false,
	weightRotationValue = 1,
})

function ik:ConstructUI(entry)
	entry.Header:SetTooltip("#tool.ragdollposer.constraint.ik.help")

	local ui, header, footer = self:ConstructUITemplate(entry, self.Properties)
end

local function createConstraint(state)
	local base = ik:Init(state)
	---@cast base IKConstraint
	return base
end

return createConstraint
