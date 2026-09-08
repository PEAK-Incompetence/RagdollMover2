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
	function binder:OnChange(newKey)
		print("new key", newKey)
		RagdollPoser.Input:RegisterKey(action, newKey)
	end
	return binder
end

local mirrorMapping = {
	[0] = "x",
	[1] = "y",
	[2] = "z",
}
local mirrorMappingInverse = table.Flip(mirrorMapping)

---@param cpanel ControlPanel
function MGR:BuildCPanel(cpanel)
	keyBinder(cpanel, "#tool.ragdollposer.cycle", "ragdollposer_cycle_key", RagdollPoser.Actions.CycleGizmo)
	keyBinder(cpanel, "#tool.ragdollposer.select", "ragdollposer_select_key", RagdollPoser.Actions.SelectBone)

	cpanel:CheckBox("#tool.ragdollposer.local", "ragdollposer_local")
	cpanel:CheckBox("#tool.ragdollposer.mirror", "ragdollposer_mirror")
	local mirrorCombo = cpanel:ComboBox("#tool.ragdollposer.mirror.axis", "ragdollposer_mirror_axis")
	mirrorCombo:AddChoice("x", 0)
	mirrorCombo:AddChoice("y", 1)
	mirrorCombo:AddChoice("z", 2)
	local id = GetConVar("ragdollposer_mirror_axis"):GetInt() + 1
	mirrorCombo:ChooseOption(mirrorMapping[id - 1], id)

	cpanel:NumSlider("#tool.ragdollposer.width", "ragdollposer_width", 0.1, 1, 2)
	cpanel:NumSlider("#tool.ragdollposer.scale", "ragdollposer_scale", 0.1, 50, 2)
end

---@param cpanel ControlPanel
function MGR:Initialize(cpanel)
	local success, msg = pcall(self.BuildCPanel, self, cpanel)
	if not success and msg then
		ErrorNoHaltWithStack(msg)
	end
end

RagdollPoser.UI = MGR

hook.Run("RagdollPoser_UI_Refresh")
