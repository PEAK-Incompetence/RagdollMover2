TOOL.Name = "#tool.ragdollposer.name"
TOOL.Category = "Poser"
TOOL.Command = nil
TOOL.ConfigName = ""

---@param pl Player
---@param entity Entity
---@param bone any
---@param entities any
local function refreshEntities(pl, entity, bone, entities)
	RagdollPoser.Networking.SendAssemblyInfo()
	net.WriteEntity(entity)
	net.WriteUInt(bone, 8)
	net.WriteUInt(#entities, 10)
	for i = 1, #entities do
		net.WriteEntity(entities[i])
	end
	net.Send(pl)
end

---@param entity Entity
local function validateEntity(entity)
	-- Send only entities with a model
	return entity.GetModel and entity:GetModel()
end

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
		local constrainedTab = constraint.GetAllConstrainedEntities(entity)
		local constrainedList = {}
		for _, ent in pairs(constrainedTab) do
			if validateEntity(ent) then
				table.insert(constrainedList, ent)
			end
		end

		-- PrintTable(constrainedList)
		if not entity.rgpbonecached then -- also taken from locrotscale. some hacky way to cache the bones?
			pl.rgpSwep = self.SWEP
			local p = pl.rgpSwep:GetParent()
			pl.rgpSwep:FollowBone(entity, 0)
			pl.rgpSwep:SetParent(p)
			entity.rgpbonecached = true
		end

		-- Send entity info to the client
		local bone = entity:TranslatePhysBoneToBone(phys)
		refreshEntities(pl, entity, bone, constrainedList)

		-- TODO: Expand this maybe, also make it use table fields if we don't plan to use this often
		RagdollPoser.Data.Players[pl] = { entity, bone, constrainedList, constrainedTab }
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
			local entities = RagdollPoser.Data.Players[pl][3]
			if entity then
				refreshEntities(pl, entity, bone, entities)
			end
		end
	end
end

if SERVER then
	return
end

---@param self TOOL
---@param cPanel ControlPanel
function TOOL.BuildCPanel(self, cPanel) end

-- Gizmo rendering entrypoint
function TOOL:DrawHUD()
	RagdollPoser.Gizmo:Render()
end
