---[CLIENT]
---
---Tool panel UI and HUD
---
---@class RagdollPoser.UI
local MGR = {}

local getModelIcon, getNiceModelName = RagdollPoser.Helpers.GetModelNodeIconPath, RagdollPoser.Helpers.GetModelNameNice

---@param cpanel ControlPanel|DForm
---@param label string
---@param cvar string
---@param action InputAction
---@param keyChangedCallback fun(newKey: BUTTON_CODE)?
---@return CtrlNumPad
local function keyBinder(cpanel, label, cvar, action, keyChangedCallback)
	---@class CtrlNumPad
	---@field NumPad1 DBinder
	local binder = cpanel:KeyBinder(label, cvar)

	local oldClick = binder.NumPad1.DoClick
	function binder.NumPad1:DoClick()
		local oldKey = self:GetValue()
		print(oldKey)
		oldClick(self)
		RagdollPoser.Input:UnregisterKey(action, oldKey)
	end

	function binder.NumPad1:OnChange(newKey)
		RagdollPoser.Input:RegisterKey(action, newKey)
		if keyChangedCallback then
			keyChangedCallback(newKey)
		end
	end
	return binder
end

---Helper for DForm
---@param cPanel ControlPanel|DForm|DCategoryList
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

---@param parent ConstraintForm
---@param entity Entity
---@param constraint Constraint
---@return ConstraintEntry
local function makeConstraintEntry(parent, entity, constraint)
	local props = constraint.Properties
	local state = constraint.State

	local index = RagdollPoser.Constraints:GetConstraintIndex(entity, constraint._id)

	---@class ConstraintEntry: ControlPanel
	---@field Header DCategoryHeader
	local entry = makeCategory(parent, "", "ControlPanel")
	entry:SetList(parent)
	parent.Items[index] = entry

	function entry.Header:DoRightClick()
		local menu = DermaMenu()

		menu:AddOption("#tool.ragdollposer.constraint.delete", function()
			RagdollPoser.Constraints:Remove(entity, constraint._id)
			entry:Remove()
		end)

		menu:Open()
	end

	-- Each constraint carries an id, so anytime we make updates to the ui, we use the id to make
	-- changes to the actual constraint object

	-- Header UI
	entry.icon = vgui.Create("DImage", entry)
	entry.name = vgui.Create("DTextEntry", entry)
	entry.enabled = vgui.Create("DCheckBox", entry)

	function entry.name:OnValueChange(newText)
		constraint.Properties.name = newText
		RagdollPoser.Constraints:UpdateConstraint(entity, constraint)
	end

	entry.enabled:SetChecked(constraint.State.enabled)
	function entry.enabled:OnChange(enabled)
		constraint.State.enabled = enabled
		RagdollPoser.Constraints:UpdateConstraint(entity, constraint)
	end

	local oldThink = entry.enabled.Think
	function entry.enabled.Think(pnl)
		oldThink(pnl)
		entry.enabled:SetChecked(constraint.State.enabled)
	end

	-- Move constraint up and down for ordering
	-- Moving this up and down triggers reconstruction, although if I could just manually swap the order here, that would be more performant
	entry.up = vgui.Create("DImageButton", entry)
	entry.down = vgui.Create("DImageButton", entry)

	entry.icon:SetKeepAspect(true)
	entry.up:SetKeepAspect(true)
	entry.down:SetKeepAspect(true)

	entry.icon:SetImage(props.icon ~= "" and props.icon or "icon16/link.png")
	entry.up:SetImage("icon16/bullet_arrow_up.png")
	entry.down:SetImage("icon16/bullet_arrow_down.png")
	entry.up:SetTooltip("#tool.ragdollposer.constraint.move.up")
	entry.down:SetTooltip("#tool.ragdollposer.constraint.move.down")

	function entry.up.DoClick()
		local stack = RagdollPoser.Constraints:GetConstraintStack(entity)
		local index = RagdollPoser.Constraints:GetConstraintIndex(entity, constraint._id)
		if index and index > 1 then
			local newIndex = index - 1
			local previousEntry = parent.Items[newIndex]
			entry:MoveToBefore(previousEntry)
			parent.Items[newIndex] = entry
			parent.Items[index] = previousEntry

			RagdollPoser.Constraints:Swap(entity, constraint, stack[newIndex])
			previousEntry.down:SetEnabled(index < #stack)
			previousEntry.up:SetEnabled(index > 1)
			entry.up:SetEnabled(newIndex > 1)
			entry.down:SetEnabled(newIndex < #stack)
		end
	end

	function entry.down.DoClick()
		local stack = RagdollPoser.Constraints:GetConstraintStack(entity)
		local index = RagdollPoser.Constraints:GetConstraintIndex(entity, constraint._id)
		if index and index < #stack then
			local newIndex = index + 1
			local nextEntry = parent.Items[newIndex]
			entry:MoveToAfter(nextEntry)
			parent.Items[newIndex] = entry
			parent.Items[index] = nextEntry

			RagdollPoser.Constraints:Swap(entity, constraint, stack[newIndex])
			nextEntry.up:SetEnabled(index > 1)
			nextEntry.down:SetEnabled(index < #stack)
			entry.up:SetEnabled(newIndex > 1)
			entry.down:SetEnabled(newIndex < #stack)
		end
	end

	local stack = RagdollPoser.Constraints:GetConstraintStack(entity)
	entry.up:SetEnabled(index > 1)
	entry.down:SetEnabled(index < #stack)

	local height = entry.Header:GetTall()
	entry.up:SetSize(height, height)
	entry.down:SetSize(height, height)
	entry.icon:SetSize(height, height)

	entry.name:SetText(language.GetPhrase(props.name) or "Constraint")
	entry.icon:SetMouseInputEnabled(false)
	-- Right click entry to access settings like renaming, copying, or duplicating

	entry.name:SetTooltip(language.GetPhrase(props.help))

	local oldLayout = entry.PerformLayout
	function entry:PerformLayout(w, h)
		oldLayout(self, w, h)
		entry.icon:SetPos(5, 0)

		entry.name:SetSize(w * 0.6, height * 0.8)
		entry.name:SetPos(entry.icon:GetWide() + 10, (height - entry.name:GetTall()) * 0.5)

		entry.enabled:SetPos(w * 0.9, 0)
		entry.up:SetPos(entry.enabled:GetX() - height, 0)
		entry.down:SetPos(entry.up:GetX() - height, 0)
	end

	-- Inside the entry, construct the ui based on the instructions from the constraint file
	entry.ui = constraint:ConstructUI(entry, props, state)

	entry.keybinder = keyBinder(
		entry,
		"#tool.ragdollposer.constraint.bind",
		"",
		RagdollPoser.Actions.ToggleConstraint,
		function(newKey)
			print("run this!")
			constraint.State.key = newKey
			RagdollPoser.Constraints:UpdateConstraint(entity, constraint)
		end
	)

	if constraint.State.key > -1 then
		entry.keybinder.NumPad1:SetValue(constraint.State.key)
	end

	return entry
end

local mirrorMapping = {
	[0] = "x",
	[1] = "y",
	[2] = "z",
}
local mirrorMappingInverse = table.Flip(mirrorMapping)

---@param entityTree EntityTree
---@param clients ClientEntity[]
---@param selectedEntities SelectedEntities
local function populateEntities(entityTree, clients, selectedEntities)
	entityTree:Clear()

	for _, entity in ipairs(clients) do
		local model = entity:GetModel()

		local node = entityTree:AddNode(getNiceModelName(entity), getModelIcon(entity)) --[[@as DTree_Node]]
		node:SetSelected(selectedEntities[entity])

		function node:DoClick()
			RagdollPoser.Selection:SelectOne(0, entity, input.IsControlDown())
			entityTree.selected = entity
			entityTree:EntitySelected(entity)
		end
		entityTree[entity] = node
	end

	-- Do check for parent entities
	for _, client in ipairs(clients) do
		local entity = RagdollPoser.Entity.GetEntityFromClient(client)
		local childNode = entityTree[client]
		local parentClient = RagdollPoser.Entity.GetClientFromEntity(entity:GetParent())
		local parentNode = IsValid(parentClient) and entityTree[parentClient]
		if parentNode then
			parentNode:CreateChildNodes()
			childNode:SetParentNode(parentNode)
			parentNode.ChildNodes:Add(childNode)
			parentNode:InvalidateLayout()
			parentNode:SetExpanded(true, true)
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
---@param entity ClientEntity
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

---@param entity ClientEntity
---@param boneIndex integer
---@return integer
local function getBoneType(entity, boneIndex)
	return RagdollPoser.Bones:GetBoneType(entity, boneIndex)
end

---Add the bone nodes for the boneTree from the puppet
---@param entity ClientEntity
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

--- @param client ClientEntity
--- @param bone integer?
--- @param keepOpen boolean?
function MGR:ConstraintMenu(client, bone, keepOpen)
	local entity = RagdollPoser.Entity.GetEntityFromClient(client)

	-- get list of constraints categories, then insert each constraint in a category
	-- click on a constraint name. we add the constraint to the entity. also send it to the server
	-- so that when we reselect entities, we also get constraint info
	-- get the constraint info, and make constraint entry based off actual constraints that exist there
	local menu = DermaMenu(keepOpen)

	local constraints = RagdollPoser.Constraints:GetConstraints()
	local categories = {}
	for _, constraint in ipairs(constraints) do
		local cat = language.GetPhrase(constraint.Properties.category)
		if cat and cat ~= "" and not categories[cat] then
			categories[cat] = {}
		end

		if categories[cat] then
			table.insert(categories[cat], constraint)
		end
	end

	for category, constraints in SortedPairs(categories) do
		local submenu = menu:AddSubMenu(category)
		for _, constraint in ipairs(constraints) do
			local name = language.GetPhrase(constraint.Properties.name)
			local option = submenu:AddOption(language.GetPhrase(name), function()
				---@type ConstraintState
				local state
				if bone then
					state = {
						target = entity,
						bone = bone or -1,
						key = BUTTON_CODE_INVALID,
						enabled = true,
						influence = 1,
					}
				end

				RagdollPoser.Constraints:Push(entity, constraint.Properties.type, state)
			end)
			option:SetTooltip(language.GetPhrase(constraint.Properties.desc))
		end
	end

	menu:Open()
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

	---@class EntityTree: rgp_tree
	---@field [ClientEntity] DTree_Node
	---@field selected ClientEntity
	local entitySelector = entitySelectorContainer:Add("rgp_tree")

	---@class BoneTree: rgp_tree
	local boneTree = boneTreeContainer:Add("rgp_tree")

	entitySelector:Dock(FILL)
	boneTree:Dock(FILL)

	populateEntities(
		entitySelector,
		RagdollPoser.Entity.GetClientEntities(),
		RagdollPoser.Selection:GetSelectedEntities()
	)
	populateBoneTree(boneTree, RagdollPoser.Selection:GetSelection())

	local constraintCategory = makeCategory(cpanel, language.GetPhrase("tool.ragdollposer.constraint"), "ControlPanel")
	local addConstraint = constraintCategory:Button(language.GetPhrase("tool.ragdollposer.constraint.add"))

	local constraintListForm =
		makeCategory(constraintCategory, language.GetPhrase("tool.ragdollposer.constraint.list"), "DForm")
	local constraintListContainer = vgui.Create("DPanel", constraintListForm)
	constraintListForm:AddItem(constraintListContainer)
	constraintListContainer:SizeTo(-1, 200, 0)
	---@class ConstraintForm: DCategoryList
	---@field Items ConstraintEntry[]
	local constraintList = vgui.Create("DCategoryList", constraintListContainer)
	constraintList:Dock(FILL)
	constraintList.Items = {}
	print("constraint list items!")
	print(constraintList.Items)

	function addConstraint:DoClick()
		MGR:ConstraintMenu(entitySelector.selected)
	end

	--- @param client ClientEntity
	local function updateConstraintUI(client)
		local entity = RagdollPoser.Entity.GetEntityFromClient(client)
		print("clear selected")
		constraintList:Clear()
		local constraints = RagdollPoser.Constraints:GetConstraintStack(entity)
		if constraints then
			for _, constraint in ipairs(constraints) do
				makeConstraintEntry(constraintList, entity, constraint)
			end
		end
	end

	---@param client ClientEntity
	function entitySelector:EntitySelected(client)
		updateConstraintUI(client)
	end

	hook.Add("RagdollPoser_Selection_Selected", "UI_UpdateEntities", function(selection, selectedEntities)
		populateEntities(entitySelector, RagdollPoser.Entity.GetClientEntities(), selectedEntities)
		updateBoneTree(boneTree, selection)
		print("selected check ui")
		PrintTable(selection)
		local selectedEntity = selection[#selection]
		entitySelector.selected = selectedEntity
		updateConstraintUI(selectedEntity)
	end)

	hook.Add("RagdollPoser_Constraints_ConstraintCreated", "UI_UpdateEntities", function(entity, constraints)
		local client = RagdollPoser.Entity.GetClientFromEntity(entity)
		print("update constraints")
		print(entity, client, entitySelector.selected, constraints)
		print("selected equals us?", entitySelector.selected == client)
		if client == entitySelector.selected then
			for _, constraint in ipairs(constraints) do
				makeConstraintEntry(constraintList, entity, constraint)
			end
		end
	end)

	hook.Add("RagdollPoser_Constraints_ConstraintOrderChanged", "UI_UpdateEntities", function(entity)
		local client = RagdollPoser.Entity.GetClientFromEntity(entity)
		print("no don't do it!")
		-- if client == entitySelector.selected then
		-- 	updateConstraintUI(client)
		-- end
	end)
end

---@param cpanel ControlPanel
function MGR:Initialize(cpanel)
	hook.Remove("RagdollPoser_Constraints_ConstraintCreated", "UI_UpdateEntities")
	hook.Remove("RagdollPoser_Selection_Selected", "UI_UpdateEntities")
	hook.Remove("RagdollPoser_Constraints_ConstraintOrderChanged", "UI_UpdateEntities")

	local success, msg = pcall(self.BuildCPanel, self, cpanel)
	if not success and msg then
		ErrorNoHaltWithStack(msg)
	end
end

RagdollPoser.UI = MGR

hook.Run("RagdollPoser_UI_Refresh")
