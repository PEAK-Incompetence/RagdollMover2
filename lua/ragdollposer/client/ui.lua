---[CLIENT]
---
---Tool panel UI and HUD
---
---@class RagdollPoser.UI
local MGR = {}

local getModelIcon, getNiceModelName = RagdollPoser.Helpers.GetModelNodeIconPath, RagdollPoser.Helpers.GetModelNameNice

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

---Helper for DForm
---@param cPanel ControlPanel|DForm
---@param name string
---@param type "ControlPanel"|"DForm"
---@return ControlPanel|DForm
local function makeCategory(cPanel, name, type)
	---@type DForm|ControlPanel
	local category = vgui.Create(type, cPanel)

	category:SetLabel(name)
	cPanel:AddItem(category)
	return category
end

local mirrorMapping = {
	[0] = "x",
	[1] = "y",
	[2] = "z",
}
local mirrorMappingInverse = table.Flip(mirrorMapping)

---@class EntityTree: DTree
---@field [Entity] DTree_Node

---@param entityTree EntityTree
---@param entities Entity[]
---@param selectedEntities SelectedEntities
local function populateEntities(entityTree, entities, selectedEntities)
	entityTree:Clear()
	for _, entity in ipairs(entities) do
		local model = entity:GetModel()

		local node = entityTree:AddNode(getNiceModelName(entity), getModelIcon(entity)) --[[@as DTree_Node]]
		node:SetSelected(selectedEntities[entity])

		function node:DoClick()
			RagdollPoser.Selection:SelectOne(0, entity, input.IsControlDown())
		end
		entityTree[entity] = node
	end

	-- Do check for parent entities
	for _, entity in ipairs(entities) do
		local childNode = entityTree[entity]
		local parentEntity = entity:GetParent()
		local parentNode = IsValid(parentEntity) and entityTree[parentEntity]
		if parentNode then
			childNode:MoveChildTo(parentNode)
		end
	end
end

local boneTypes = {
	[RagdollPoser.Bones.BoneType.Physics] = "icon16/brick.png",
	[RagdollPoser.Bones.BoneType.Manipulate] = "icon16/connect.png",
	[RagdollPoser.Bones.BoneType.Procedural] = "icon16/error.png",
	[RagdollPoser.Bones.BoneType.Jiggle] = "icon16/error.png",
	-- [RagdollPoser.Bones.BoneType.Locked] = "icon16/lock.png",
}

---From Ragdoll Puppeteer
---@class BoneTreeNode: DTree_Node

---@param node DTree_Node
---@return DTree_Node root
local function getRootNode(node)
	local walk = node
	while walk:GetParentNode() ~= node:GetRoot() do
		walk = walk:GetParentNode()
	end
	return walk
end

---@param parentNode DTree|BoneTreeNode
---@param entity Entity
---@param bone integer
---@param boneName string
---@param boneType BoneType
---@return BoneTreeNode
local function addBoneNode(parentNode, entity, bone, boneName, boneType)
	local child = parentNode:AddNode(boneName) --[[@as DTree_Node]]
	---@cast child BoneTreeNode
	child.boneIcon = boneTypes[boneType]
	child.bone = bone
	child:SetIcon(child.boneIcon)
	child:SetExpanded(true, false)

	function child:DoClick()
		local root = getRootNode(self)
		if not input.IsShiftDown() then
			root.SelectedNode = self
		end
		if input.IsShiftDown() and IsValid(root.SelectedNode) then
			local selection = {}
			local nodes = {}

			---@param node DTree_Node
			---@param nodes DTree_Node[]
			local function collectVisibleNodes(node, nodes)
				if not IsValid(node) then
					return
				end

				if not node:IsRootNode() then
					nodes[#nodes + 1] = node
				end

				if not node:GetExpanded() then
					return
				end

				for _, child in ipairs(node:GetChildNodes()) do
					if child:IsVisible() then
						collectVisibleNodes(child, nodes)
					end
				end
			end

			local anchorIndex
			collectVisibleNodes(root, nodes)
			for index, node in ipairs(nodes) do
				if node == root.SelectedNode then
					anchorIndex = index
					break
				end
			end

			for i = anchorIndex, #nodes do
				local node = nodes[i]
				local bone = node.bone
				table.insert(selection, bone)
				table.insert(selection, entity)

				if node == child then
					break
				end
			end

			RagdollPoser.Selection:SelectGroup(selection, input.IsControlDown())
		else
			RagdollPoser.Selection:SelectOne(bone, entity, input.IsControlDown())
		end
	end

	return child
end

---@param entity Entity
---@param boneIndex integer
---@return integer
local function getBoneType(entity, boneIndex)
	return RagdollPoser.Bones:GetBoneType(entity, boneIndex)
end

---Add the bone nodes for the boneTree from the puppet
---@param entity Entity
---@param boneTree DTree
local function setupBoneNodesOf(entity, boneTree)
	boneTree.nodes = {}
	---@type BoneTreeNode[]
	local parentSet = {}
	for b = 0, entity:GetBoneCount() - 1 do
		if entity:GetBoneName(b) == "__INVALIDBONE__" then
			continue
		end

		RagdollPoser.Entity.ExposeBones(entity)

		local boneType = getBoneType(entity, b)

		local parent = entity:GetBoneParent(b)
		if parent > -1 and parentSet[parent] then
			local node = addBoneNode(parentSet[parent], entity, b, entity:GetBoneName(b), boneType)
			parentSet[b] = node
			parentSet[b].boneId = b
		else
			local node = addBoneNode(boneTree, entity, b, entity:GetBoneName(b), boneType)
			parentSet[b] = node
			parentSet[b].boneId = b
		end
	end
	boneTree.nodes = parentSet
end

---@param boneTree DTree
---@param selection Selection
local function populateBoneTree(boneTree, selection)
	boneTree:Clear()
	boneTree.Entities = {}

	for i = 1, #selection - 1, 2 do
		local bone = selection[i] --[[@as integer]]
		local entity = selection[i + 1] --[[@as ClientEntity]]

		local boneRoot = boneTree.Entities[entity]
		if not boneTree.Entities[entity] then
			boneRoot = boneTree:AddNode(getNiceModelName(entity), getModelIcon(entity)) --[[@as DTree]]
			boneRoot:SetExpanded(true)
			setupBoneNodesOf(entity, boneRoot)
			boneTree.Entities[entity] = boneRoot
		end

		boneRoot.nodes[bone]:SetSelected(true)
	end
end

local function updateBoneTree(boneTree, selection)
	for _, rootNode in pairs(boneTree.Entities) do
		for _, node in pairs(rootNode.nodes) do
			node:SetSelected(false)
		end
	end

	local selected = {}
	for i = 1, #selection - 1, 2 do
		local bone = selection[i] --[[@as integer]]
		local entity = selection[i + 1] --[[@as ClientEntity]]

		local boneRoot = boneTree.Entities[entity]
		if not boneTree.Entities[entity] then
			boneRoot = boneTree:AddNode(getNiceModelName(entity), getModelIcon(entity)) --[[@as DTree]]
			boneRoot:SetExpanded(true)
			boneRoot:SetSelectable(false)
			setupBoneNodesOf(entity, boneRoot)
			boneTree.Entities[entity] = boneRoot
		end

		selected[entity] = true
		boneRoot.nodes[bone]:SetSelected(true)
	end

	for entity, node in pairs(boneTree.Entities) do
		if not selected[entity] then
			node:Remove()
			boneTree.Entities[entity] = nil
		end
	end
end

---@param cpanel ControlPanel
function MGR:BuildCPanel(cpanel)
	local gizmoCategory = makeCategory(cpanel, language.GetPhrase("#tool.ragdollposer.gizmo"), "ControlPanel")
	gizmoCategory:CheckBox("#tool.ragdollposer.local", "ragdollposer_local")
	gizmoCategory:NumSlider("#tool.ragdollposer.scale", "ragdollposer_scale", 0.1, 50, 2)
	gizmoCategory:NumSlider("#tool.ragdollposer.width", "ragdollposer_width", 0.1, 1, 2)
	keyBinder(gizmoCategory, "#tool.ragdollposer.cycle", "ragdollposer_cycle_key", RagdollPoser.Actions.CycleGizmo)

	local gizmoOffsets =
		makeCategory(gizmoCategory, language.GetPhrase("#tool.ragdollposer.gizmo.offset"), "ControlPanel")

	local boneManip = makeCategory(cpanel, language.GetPhrase("tool.ragdollposer.bone.manip"), "ControlPanel")
	boneManip:CheckBox("#tool.ragdollposer.mirror", "ragdollposer_mirror")
	local mirrorCombo = boneManip:ComboBox("#tool.ragdollposer.mirror.axis", "ragdollposer_mirror_axis")
	mirrorCombo:AddChoice("x", 0)
	mirrorCombo:AddChoice("y", 1)
	mirrorCombo:AddChoice("z", 2)
	local id = GetConVar("ragdollposer_mirror_axis"):GetInt() + 1
	mirrorCombo:ChooseOption(mirrorMapping[id - 1], id)

	keyBinder(boneManip, "#tool.ragdollposer.select", "ragdollposer_select_key", RagdollPoser.Actions.SelectBone)

	local boneTreeCategory = makeCategory(boneManip, language.GetPhrase("tool.ragdollposer.bone.tree"), "ControlPanel")

	local panelContainer = vgui.Create("DPanel", boneTreeCategory)
	panelContainer:SizeTo(-1, 400, 0)
	boneTreeCategory:AddItem(panelContainer)
	local divider = panelContainer:Add("DHorizontalDivider")
	divider:Dock(FILL)

	local entitySelectorContainer = vgui.Create("DPanel", boneTreeCategory)
	local boneTreeContainer = vgui.Create("DPanel", boneTreeCategory)
	divider:SetLeft(entitySelectorContainer)
	divider:SetRight(boneTreeContainer)

	local entitySelector = entitySelectorContainer:Add("rgp_tree")
	local boneTree = boneTreeContainer:Add("rgp_tree")

	entitySelector:Dock(FILL)
	boneTree:Dock(FILL)

	populateEntities(
		entitySelector,
		RagdollPoser.Entity.GetClientEntities(),
		RagdollPoser.Selection:GetSelectedEntities()
	)
	populateBoneTree(boneTree, RagdollPoser.Selection:GetSelection())

	hook.Add("RagdollPoser_Selection_Selected", "UI_UpdateEntities", function(selection, selectedEntities)
		populateEntities(entitySelector, RagdollPoser.Entity.GetClientEntities(), selectedEntities)
		updateBoneTree(boneTree, selection)
	end)
end

---@param cpanel ControlPanel
function MGR:Initialize(cpanel)
	hook.Remove("RagdollPoser_Selection_Selected", "UI_UpdateEntities")

	local success, msg = pcall(self.BuildCPanel, self, cpanel)
	if not success and msg then
		ErrorNoHaltWithStack(msg)
	end
end

RagdollPoser.UI = MGR

hook.Run("RagdollPoser_UI_Refresh")
