---[CLIENT]
---
---Tool panel UI and HUD
---
---@class RagdollPoser.UI
local MGR = {}

---@param cpanel ControlPanel
function MGR:BuildCPanel(cpanel)
	local binder = cpanel:KeyBinder("#tool.ragdollposer.cycle.label", "ragdollposer_cycle_key")
	function binder:OnChange(newKey) end
end

---@param cpanel ControlPanel
function MGR:Initialize(cpanel)
	self:BuildCPanel(cpanel)
end

RagdollPoser.UI = MGR
