---@class Constraint
---@field State ConstraintState
---@field Properties ConstraintProps
local Base = {}
Base.__index = Base

Base._id = 0

---@class ConstraintProps
Base.Properties = {
	type = "base",
	category = "",
	name = "",
	desc = "",
}

---@class ConstraintState
Base.State = {
	target = NULL,
	bone = -1,
	influence = 1,
}

---@param entry ConstraintEntry
---@param props ConstraintProps
function Base:ConstructUITemplate(entry, props)
	local ui = {}

	local function header()
		-- entity to target
		ui.target = entry:TextEntry(string.NiceName(language.GetPhrase(props.name)), "")
		-- bone of entity to target
		ui.bone = entry:TextEntry("#tool.ragdollposer.constraint.bone", "")

		-- Instead of typing directly into the forms, open up a menu for available bones with a floating search entry
		ui.target:SetEditable(false)
		ui.bone:SetEditable(false)

		function ui.target.OnMousePressed(base, mousecode)
			if mousecode == MOUSE_LEFT then
				local menu = DermaMenu()

				local selection = RagdollPoser.Selection:GetSelection()
				for i = 1, #selection - 1, 2 do
					local bone = selection[i] ---@as integer
					local entity = selection[i + 1] ---@as Entity
					local model = RagdollPoser.Helpers.GetModelNameNice(entity)
					local name = Format("%s: %s", model, tostring(entity))
					menu:AddOption(name, function()
						self.State.target = entity
						base:SetText(name)
					end)
				end

				menu:Open()
			elseif mousecode == MOUSE_RIGHT then
				local menu = DermaMenu()

				menu:AddOption("#tool.ragdollposer.constraint.target.unset", function()
					self.State.target = NULL
					base:SetText("")
				end)
				menu:AddOption("#tool.ragdollposer.constraint.target.set.picker", function() end)

				menu:Open()
			end
		end
	end

	-- implement ui bone stuff using bone search utility from ragdoll puppeteer

	local function footer()
		ui.influence = entry:NumSlider("#tool.ragdollposer.constraint.influence", "", 0, 1, 3)

		function ui.influence.OnValueChanged(base, newValue)
			self.State.influence = newValue
		end
	end

	-- Give explicit builder functions for UI. That way, we can define stuff in between our header and footers
	return ui, header, footer
end

---@param entry ConstraintEntry
---@return table<any, Panel>
function Base:ConstructUI(entry) end

function Base:Init(state)
	local id = self._id + 1

	local base = setmetatable({
		_id = id,
		State = state or table.Copy(self.State),
	}, Base)
	self._id = id
	return base
end

-- Save some bone info here
function Base:PreEvaluate() end

function Base:Evaluate() end

function Base:PostEvaluate() end

return Base
