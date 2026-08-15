TOOL.Name = "#tool.ragdollposer.name"
TOOL.Category = "Poser"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar["width"] = 0.25
TOOL.ClientConVar["scale"] = 30
TOOL.ClientConVar["partial"] = 1

---@param tr TraceResult
function TOOL:LeftClick(tr)
	local pl = self:GetOwner()
	tr = util.TraceLine({
		start = tr.StartPos,
		endpos = tr.StartPos + pl:GetAimVector() * 16384,
		filter = { pl, pl:GetViewEntity() },
		ignoreworld = false, -- TODO: implement ignore world privileges
	})

	if CLIENT then
		return false
	end

	local data = RagdollPoser.Data.Players[pl]
	local entity = tr.Entity
	local phys = tr.PhysicsBone
	if
		entity
		and IsValid(entity)
		and not (data[4] and data[4][entity])
		and phys
		and entity:GetPhysicsObjectNum(phys)
	then
		local constrainedList, constrainedTab = RagdollPoser.Data.GetConstrainedEntities(entity)

		-- PrintTable(constrainedList)
		if not entity.rgpbonecached then -- also taken from locrotscale. some hacky way to cache the bones?
			pl.rgpSwep = self.SWEP
			local p = pl.rgpSwep:GetParent()
			pl.rgpSwep:FollowBone(entity, 0)
			pl.rgpSwep:SetParent(p)
			entity.rgpbonecached = true
		end

		-- Send entity info to the client
		local bone = math.max(entity:TranslatePhysBoneToBone(phys), 0)
		RagdollPoser.Data.RefreshEntities(pl, entity, bone, constrainedList)
		RagdollPoser.Data.UpdatePhysBoneCount(entity)
		RagdollPoser.Data:Update(pl, entity, bone, constrainedList, constrainedTab)
	end

	return false
end

---@param tr TraceResult
function TOOL:RightClick(tr) end

function TOOL:Deploy()
	if SERVER then
		local pl = self:GetOwner()
		if RagdollPoser.Data.Players[pl] then
			local entity = RagdollPoser.Data.Players[pl][1]
			local bone = RagdollPoser.Data.Players[pl][2]
			if IsValid(entity) then
				local entities, constrainedEntities = RagdollPoser.Data.GetConstrainedEntities(entity)
				RagdollPoser.Data.RefreshEntities(pl, entity, bone, entities)
				RagdollPoser.Data:Update(pl, entity, bone, entities, constrainedEntities)
			end
		end
	end
end

if SERVER then
	return
end

local cvars = TOOL:BuildConVarList()

local firstBuilt = false
function TOOL:Think()
	if not firstBuilt then
		firstBuilt = true
		self:RebuildControlPanel()
	end
end

---@param cPanel ControlPanel
function TOOL.BuildCPanel(cPanel)
	RagdollPoser.UI:Initialize(cPanel)
end

-- Gizmo rendering entrypoint
function TOOL:DrawHUD()
	RagdollPoser.Gizmo:Render()
end

hook.Add("RagdollPoser_UI_Refresh", "ToolUI", function()
	local tool = LocalPlayer():GetTool(RagdollPoser.Mode)
	tool:RebuildControlPanel()
end)
