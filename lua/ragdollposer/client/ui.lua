---[CLIENT]
---
---Tool panel UI and HUD
---
---@class RagdollPoser.UI
local MGR = {}

---@param cpanel ControlPanel
---@param label string
---@param cvar string
---@return DBinder
local function keyBinder(cpanel, label, cvar, action)
	local binder = cpanel:KeyBinder(label, cvar)
	---@cast binder DBinder
	function binder:OnChange(newKey)
		print("new key", newKey)
		RagdollPoser.Input:RegisterKey(action, newKey)
	end
	return binder
end

---@param cpanel ControlPanel
function MGR:BuildCPanel(cpanel)
	keyBinder(cpanel, "#tool.ragdollposer.cycle", "ragdollposer_cycle_key", RagdollPoser.Actions.CycleGizmo)
	keyBinder(cpanel, "#tool.ragdollposer.select", "ragdollposer_select_key", RagdollPoser.Actions.SelectBone)

	cpanel:NumSlider("#tool.ragdollposer.width", "ragdollposer_width", 0.1, 1, 2)
	cpanel:NumSlider("#tool.ragdollposer.scale", "ragdollposer_scale", 0.1, 50, 2)
end

---@param cpanel ControlPanel
function MGR:Initialize(cpanel)
	print("lol")
	self:BuildCPanel(cpanel)
end

hook.Run("RagdollPoser_UI_Refresh")

RagdollPoser.UI = MGR
