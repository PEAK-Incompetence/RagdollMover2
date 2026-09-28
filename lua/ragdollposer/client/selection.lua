---@alias SelectionEvenIndex ClientEntity
---@alias SelectionOddIndex integer

---@alias Selection (SelectionEvenIndex|SelectionOddIndex)[]
---@alias SelectedEntities table<Entity, true>

---Entity bone pair. The iteration is as follows
---
---```lua
--- for i = 1, 4, 2 do
---     local bone = entityBonePairs[i]
---     local entity = entityBonePairs[i+1]
--- end
---```
---@type Selection
local entityBonePairs = {}

---@type SelectedEntities
local selectedEntities = {}

---Entity bone pair set, so that we don't transform a bone more than once
local entitySelectedBones = {}

local MAX_BONE_COLLISION = RagdollPoser.Constants.MAX_BONE_COLLISION ^ 2

---[CLIENT]
---
---System for the currently selected bones and affiliated entities
---
---@class RagdollPoser.Selection
local MGR = {
	_enabled = false,
	_wasOnBone = false,

	_dragX = -1,
	_dragY = -1,

	_busy = false,
}

function MGR:StartDrag(x, y)
	self._dragX = x
	self._dragy = y
end

function MGR:EndDrag()
	self._dragX = -1
	self._dragy = -1
end

---@param bone integer
---@param entity Entity
---@param accumulate boolean
function MGR:SelectOne(bone, entity, accumulate)
	RagdollPoser.Log("selected", bone, entity)
	-- Accumulate selections if we want to manipulate them all at once

	entitySelectedBones[entity] = entitySelectedBones[entity] or {}
	if accumulate then
		if not entitySelectedBones[entity][bone] then
			local count = #entityBonePairs + 1
			entityBonePairs[count] = bone
			entityBonePairs[count + 1] = entity
			entitySelectedBones[entity][bone] = true
			selectedEntities[entity] = true
		end
	else
		selectedEntities = {}
		entitySelectedBones[entity] = {}
		entityBonePairs = { bone, entity }
		entitySelectedBones[entity][bone] = true
		selectedEntities[entity] = true
	end

	hook.Run("RagdollPoser_Selection_Selected", entityBonePairs, selectedEntities)
end

---@param selection Selection
function MGR:SelectGroup(selection, accumulate)
	if not accumulate then
		entityBonePairs = {}
		entitySelectedBones = {}
		selectedEntities = {}
	end
	local count = accumulate and #entityBonePairs or 0
	local j = 0
	for i = 1, #selection - 1, 2 do
		local bone, entity = selection[i], selection[i + 1]

		entitySelectedBones[entity] = entitySelectedBones[entity] or {}
		selectedEntities[entity] = true
		if not entitySelectedBones[entity][bone] then
			j = j + 1
			entityBonePairs[count + j] = bone
			entityBonePairs[count + j + 1] = entity
			j = j + 1
			entitySelectedBones[entity][bone] = true
		end
	end

	hook.Run("RagdollPoser_Selection_Selected", entityBonePairs, selectedEntities)
end

function MGR:GetSelection()
	return entityBonePairs
end

function MGR:Unselect()
	entityBonePairs = {}
	hook.Run("RagdollPoser_Selection_Selected", entityBonePairs, selectedEntities)
end

---Temporary list for refreshing entities when re-deploying the tool
local entityIndices = {}
hook.Add("RagdollPoser_Entity_PreRefresh", "Selection", function(clientToEntity)
	for i = 2, #entityBonePairs, 2 do
		local entity = clientToEntity[entityBonePairs[i]]
		table.insert(entityIndices, entity)
		table.insert(entityIndices, i)
	end
end)

hook.Add("RagdollPoser_Entity_PostRefresh", "Selection", function(entityToClient)
	for i = 1, #entityIndices - 1, 2 do
		local client = entityToClient[entityIndices[i]]
		-- If the entity we're selecting is about to be removed, then stop refresh
		if client:IsMarkedForDeletion() then
			entityBonePairs = {}
			break
		end
		entityBonePairs[entityIndices[i + 1]] = client
	end
	entityIndices = {}
	hook.Run("RagdollPoser_Selection_Selected", entityBonePairs, selectedEntities)
end)

function MGR:GetEnabled()
	return self._enabled
end

---@param enabled boolean
function MGR:SetEnabled(enabled)
	MGR:SetWasOnBone(false)
	self._enabled = enabled
end

function MGR:IsBusy()
	return self._busy
end

function MGR:SetBusy(busy)
	self._busy = busy
end

function MGR:WasOnBone()
	return self._wasOnBone
end

---@param state boolean
function MGR:SetWasOnBone(state)
	self._wasOnBone = state
end

---@param x integer
---@param y integer
---@param tx integer
---@param ty integer
function MGR:RaycastBone(x, y, tx, ty)
	local dist = math.abs((x - tx) ^ 2 + (y - ty) ^ 2)
	return dist < MAX_BONE_COLLISION
end

local min, max = math.min, math.max
---Find the distance from a point to a line **segment**
---@param x0 integer
---@param y0 integer
---@param x1 integer
---@param y1 integer
---@param x2 integer
---@param y2 integer
function MGR:RaycastBoneLine(x0, y0, x1, y1, x2, y2)
	local dx = x2 - x1
	local dy = y2 - y1
	local Lsq = dx ^ 2 + dy ^ 2
	if Lsq == 0 then
		-- Rather than choosing between two points, don't choose at all
		return false
	end
	local t = ((x0 - x1) * dx + (y0 - y1) * dy) / Lsq
	-- TODO: Test other selection radii and find line of best fit
	-- x = 24 => y = 0.25 at 1080p
	-- Prevents double selecting the bone itself and the line segment that the bone encompasses
	local offset = 0.3
	local tClamped = max(offset, min(1 - offset, t))
	local xc = x1 + tClamped * dx
	local yc = y1 + tClamped * dy
	local distSq = (x0 - xc) ^ 2 + (y0 - yc) ^ 2

	return distSq < MAX_BONE_COLLISION
end

function MGR:GetSelectedEntities()
	return selectedEntities
end

local matrix = Matrix()
---@type Selection
local selectionBuffer = {}
---@param x integer
---@param y integer
local function getBones(x, y)
	selectionBuffer = {}
	local entities = RagdollPoser.Entity.GetClientEntities()
	local bones = RagdollPoser.Bones
	local boneTypes = bones.BoneType
	for _, entity in ipairs(entities) do
		RagdollPoser.Entity.ExposeBones(entity)
		for b = 0, entity:GetBoneCount() - 1 do
			if entity:GetBoneName(b) == "__INVALIDBONE__" then
				continue
			end
			local boneType = bones:GetBoneType(entity, b)

			entity:CopyBoneMatrix(b, matrix)
			local screenData = matrix and matrix:GetTranslation():ToScreen()
			local onBone = MGR:RaycastBone(x, y, screenData.x, screenData.y)

			local childSelected = false
			for _, childBone in ipairs(entity:GetChildBones(b)) do
				entity:CopyBoneMatrix(childBone, matrix)
				local parentScreenData = matrix and matrix:GetTranslation():ToScreen()
				if
					not onBone
					and not childSelected
					and parentScreenData
					and parentScreenData.visible
					and MGR:RaycastBoneLine(x, y, screenData.x, screenData.y, parentScreenData.x, parentScreenData.y)
				then
					MGR:SetWasOnBone(true)
					table.insert(selectionBuffer, b)
					table.insert(selectionBuffer, entity)
					childSelected = true
				end
			end
			if screenData and screenData.visible and onBone then
				MGR:SetWasOnBone(true)
				table.insert(selectionBuffer, b)
				table.insert(selectionBuffer, entity)
			end
		end
	end
end

local function handleMultipleBones(selection)
	-- TODO: make a nicer menu
	gui.EnableScreenClicker(true)
	local entities = {}
	for i = 1, #selection - 1, 2 do
		local bone, entity = selection[i], selection[i + 1]
		if not entities[entity] then
			entities[entity] = {}
		end
		table.insert(entities[entity], bone)
	end
	local menu = DermaMenu()
	for entity, bones in pairs(entities) do
		local submenu = menu:AddSubMenu(entity:GetModel())
		for _, bone in ipairs(bones) do
			local option = submenu:AddOption(entity:GetBoneName(bone), function()
				MGR:SelectOne(bone, entity, input.IsShiftDown())
			end)

			function option:TestHover()
				hook.Run("RagdollPoser_Selection_Hover", bone, entity)
			end
		end
	end

	function menu:OnRemove()
		MGR:SetBusy(false)
		gui.EnableScreenClicker(false)
	end

	local x = input.GetCursorPos()
	-- Open it twice. Why? So that we can offset it when the internals performs all the positioning
	menu:Open(x)
	local w = menu:GetWide()
	x = math.min(x, ScrW()) - w * 0.99
	menu:Open(x)
end

local function onLeftClickDown(x, y, tr)
	if not MGR:GetEnabled() then
		return
	end
	if MGR:IsBusy() then
		return
	end

	-- If we were on a bone, then set wasOnBone = true
	getBones(x, y)
	if #selectionBuffer == 0 then
		-- Start selecting bones in a box
		MGR:StartDrag(x, y)
	end
end

local function onLeftClickUp(x, y, tr)
	if not MGR:GetEnabled() then
		return
	end

	-- If we were on the gizmo on leftclickdown and we're now on it, then accept input
	-- If our mouse was on a bone, and we're still on the same bone, select it
	-- Otherwise, finish selection
	if MGR:WasOnBone() and not MGR:IsBusy() then
		getBones(x, y)
		if #selectionBuffer > 2 then
			PrintTable(selectionBuffer)
			if not input.IsShiftDown() then
				MGR:SetBusy(true)
				handleMultipleBones(selectionBuffer)
			else
				MGR:SelectGroup(selectionBuffer, input.IsShiftDown())
			end
		else
			local bone = selectionBuffer[1]
			local entity = selectionBuffer[2]
			---@cast bone SelectionOddIndex
			---@cast entity SelectionEvenIndex
			MGR:SelectOne(bone, entity, input.IsShiftDown())
		end
		MGR:SetWasOnBone(false)
	else
		-- -- do drag select
		-- MGR:SelectGroup(selectionBuffer)
		-- MGR:EndDrag()
	end
end

hook.Add("RagdollPoser_Input_LeftClickDown", "Select", onLeftClickDown)
hook.Add("RagdollPoser_Input_LeftClickUp", "Select", onLeftClickUp)

RagdollPoser.Selection = MGR
