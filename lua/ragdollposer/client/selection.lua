---Entity bone pair. The iteration is as follows
---
---```lua
--- for i = 1, 4, 2 do
---     local bone = entityBonePairs[i]
---     local entity = entityBonePairs[i+1]
--- end
---```
local entityBonePairs = {}

local MAX_BONE_COLLISION = RagdollPoser.Constants.MAX_BONE_COLLISION ^ 2

---@alias Selection {[1]: integer, [2]: Entity}

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
function MGR:SelectOne(bone, entity)
	RagdollPoser.Log("selected", bone, entity)
	-- Accumulate selections if we want to manipulate them all at once
	if input.IsShiftDown() then
		local count = #entityBonePairs + 1
		entityBonePairs[count] = bone
		entityBonePairs[count + 1] = entity
	else
		entityBonePairs = { bone, entity }
	end

	hook.Run("RagdollPoser_Selection_Selected", entityBonePairs)
end

---@param selection Selection[]
function MGR:SelectGroup(selection)
	local accumulate = input.IsShiftDown()
	if not accumulate then
		entityBonePairs = {}
	end
	local count = accumulate and #entityBonePairs or 0
	for i = 1, #selection - 1, 2 do
		local bone, entity = selection[i], selection[i + 1]
		entityBonePairs[count + i] = bone
		entityBonePairs[count + i + 1] = entity
	end

	hook.Run("RagdollPoser_Selection_Selected", entityBonePairs)
end

function MGR:GetSelection()
	return entityBonePairs
end

function MGR:Unselect()
	entityBonePairs = {}
	hook.Run("RagdollPoser_Selection_Selected", entityBonePairs)
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
	hook.Run("RagdollPoser_Selection_Selected", entityBonePairs)
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

local matrix = Matrix()
local selectionBuffer = {}
---@param x integer
---@param y integer
local function getBones(x, y)
	selectionBuffer = {}
	local entities = RagdollPoser.Entity.GetClientEntities()
	for _, entity in ipairs(entities) do
		entity:SetupBones()
		entity:InvalidateBoneCache()
		for b = 0, entity:GetBoneCount() - 1 do
			if entity:GetBoneName(b) == "__INVALIDBONE__" then
				continue
			end
			entity:CopyBoneMatrix(b, matrix)
			local screenData = matrix and matrix:GetTranslation():ToScreen()
			if screenData and screenData.visible and MGR:RaycastBone(x, y, screenData.x, screenData.y) then
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
				MGR:SelectOne(bone, entity)
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

---@type InputCallback
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
			if not input.IsShiftDown() then
				MGR:SetBusy(true)
				handleMultipleBones(selectionBuffer)
			else
				MGR:SelectGroup(selectionBuffer)
			end
		else
			MGR:SelectOne(selectionBuffer[1], selectionBuffer[2])
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
