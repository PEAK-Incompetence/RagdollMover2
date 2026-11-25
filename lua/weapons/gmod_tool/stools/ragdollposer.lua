---@class TOOL.ragdollposer: TOOL
---@field SWEP Entity
local TOOL = TOOL

TOOL.Name = "#tool.ragdollposer.name"
TOOL.Category = "Poser"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar["width"] = 0.25
TOOL.ClientConVar["scale"] = 30
TOOL.ClientConVar["partial"] = 1
TOOL.ClientConVar["local"] = 0
TOOL.ClientConVar["localoffset"] = 0
TOOL.ClientConVar["relativerotate"] = 0
TOOL.ClientConVar["xray"] = 0
TOOL.ClientConVar["drawsphere"] = 1
TOOL.ClientConVar["funsubtitles"] = 1
TOOL.ClientConVar["selection"] = 1
TOOL.ClientConVar["snap"] = 0
TOOL.ClientConVar["snap_value"] = 45
TOOL.ClientConVar["skeleton"] = 0

---@param tr TraceResult
function TOOL:LeftClick(tr)
	local pl = self:GetOwner()

	tr = util.TraceLine({
		start = tr.StartPos,
		endpos = tr.StartPos + pl:GetAimVector() * 16384,
		filter = { pl, pl:GetViewEntity() },
		ignoreworld = RagdollPoser.Helpers.CanXRaySelect(pl, tobool(self:GetClientBool("xray"))),
	})

	if pl:KeyDown(IN_USE) and tr.HitPos then
		RagdollPoser.Data:SetOffset(pl, tr.HitPos)
		return true
	end

	local entity = tr.Entity

	if IsValid(entity) and not entity:CPPICanTool(pl, self.Mode) then
		return false
	end

	if CLIENT then
		return false
	end

	if not self:GetClientBool("selection") then
		pl:SendLua('notification.AddLegacy(language.GetPhrase("#tool.ragdollposer.selection.failed"), NOTIFY_ERROR, 3)')
		return false
	end

	local data = RagdollPoser.Data.Players[pl]
	if data.Hovering then
		return false
	end

	local entitySet = data.SelectedEntitySet
	local phys = tr.PhysicsBone
	if
		entity
		and IsValid(entity)
		and not (entitySet and entitySet[entity])
		and phys
		and entity:GetPhysicsObjectNum(phys)
	then
		local constrainedList, constrainedTab = RagdollPoser.Data.GetConstrainedEntities(entity)
		local constraints = data.Constraints or {}

		if not entity.rgpbonecached then -- also taken from locrotscale. some hacky way to cache the bones?
			pl.rgpSwep = self.SWEP
			local p = pl.rgpSwep:GetParent()
			pl.rgpSwep:FollowBone(entity, 0)
			pl.rgpSwep:SetParent(p)
			entity.rgpbonecached = true
		end

		-- Send entity info to the client
		local bone = math.max(entity:TranslatePhysBoneToBone(phys), 0)
		RagdollPoser.Data:RefreshEntities(pl, entity, bone, constrainedList, constraints)
		RagdollPoser.Data:UpdatePhysBoneCount(entity, entity:GetPhysicsObjectCount())
		RagdollPoser.Data:Update(pl, entity, bone, constrainedList, constrainedTab)
	end

	return false
end

---@param tr TraceResult
function TOOL:RightClick(tr) end

function TOOL:Deploy()
	if SERVER then
		local pl = self:GetOwner()
		local data = RagdollPoser.Data.Players[pl]
		if data then
			local entity = data.SelectedEntity
			local bone = data.SelectedBone
			local constraints = data.Constraints or {}
			if IsValid(entity) then
				local entities, constrainedEntities = RagdollPoser.Data.GetConstrainedEntities(entity)
				RagdollPoser.Data:RefreshEntities(pl, entity, bone, entities, constraints)
				RagdollPoser.Data:Update(pl, entity, bone, entities, constrainedEntities)
			end
		end
	end
end

-- Lose everything if you die.
local function clearOwners(pl)
	local data = RagdollPoser.Data.Players[pl]
	local entity = data.SelectedEntity
	if IsValid(entity) then
		entity:CPPISetOwner(NULL)
		local entities, constrainedEntities = RagdollPoser.Data.GetConstrainedEntities(entity)
		for _, e in ipairs(entities) do
			e:CPPISetOwner(NULL)
		end
	end
	RagdollPoser.Data:RefreshEntities(pl, NULL, 0, {}, {})
	RagdollPoser.Data:Update(player, nil, nil, nil, nil)
	data.Hovering = false
end
hook.Add("PostPlayerDeath", "RagdollPoser_ClearOwners", clearOwners)

if SERVER then
	return
end

local cvars = TOOL:BuildConVarList()

---@param cPanel ControlPanel
function TOOL.BuildCPanel(cPanel)
	RagdollPoser.UI:Initialize(cPanel)
end

-- Gizmo rendering entrypoint
function TOOL:DrawHUD()
	RagdollPoser.Gizmo:Render()
	RagdollPoser.UI:Draw()
end

hook.Add("RagdollPoser_UI_Refresh", "ToolUI", function()
	local tool = LocalPlayer():GetTool(RagdollPoser.Mode)
	---@cast tool TOOL
	tool:RebuildControlPanel()
end)

TOOL.Information = {
	{ name = "left" },
	{ name = "left_use", icon2 = "gui/e.png" },
	{ name = "info_advselect" },
	{ name = "info_c" },
}
