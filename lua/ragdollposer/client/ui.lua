if RagdollPoser.UI and IsValid(RagdollPoser.UI.ConstraintFrame) then
	RagdollPoser.UI.ConstraintFrame:Remove()
	RagdollPoser.UI.ConstraintFrame = nil
end

---[CLIENT]
---
---Tool panel UI and HUD
---
---@class RagdollPoser.UI
local MGR = {}

---@enum BoneCategory
MGR.BoneCategory = {
	All = 0,
	Phys = 1,
	NonPhys = 2,
}

MGR.DnDTag = "rgp_constraint_dnd"

local categoryToType = {
	[MGR.BoneCategory.Phys] = RagdollPoser.Bones.BoneType.Physics,
	[MGR.BoneCategory.NonPhys] = RagdollPoser.Bones.BoneType.Manipulate,
}

---@param category BoneCategory
---@return boolean|BoneType
function MGR:CategoryToType(category)
	return category ~= self.BoneCategory.All and categoryToType[category]
end

local getModelIcon, getNiceModelName = RagdollPoser.Helpers.GetModelNodeIconPath, RagdollPoser.Helpers.GetModelNameNice

---@class KeyBinderProps
---@field label string
---@field cvar string
---@field action InputAction
---@field keyChangedCallback fun(newKey: BUTTON_CODE)?

---@class ConstraintListLayout: DListLayout
---@field DropAction_Normal fun(self: ConstraintListLayout, Drops: table<ConstraintEntry>, bDoDrop: boolean, Command: string, x: integer, y: integer)
---@field DropAction_Simple fun(self: ConstraintListLayout, Drops: table<ConstraintEntry>, bDoDrop: boolean, Command: string, x: integer, y: integer)

---@param listLayout ConstraintListLayout
local function constraintListHook(listLayout)
	function listLayout:DropAction_Simple(Drops, bDoDrop, Command, x, y)
		self:SetDropTarget(0, 0, self:GetWide(), 2)

		if bDoDrop then
			for k, v in pairs(Drops) do
				v = v:OnDrop(self)
				v:SetParent(self)
			end

			--self:OnModified()
		end
	end

	function listLayout:DropAction_Normal(Drops, bDoDrop, Command, x, y)
		local closest = self:GetClosestChild(x, y)
		if not IsValid(closest) then
			return self:DropAction_Simple(Drops, bDoDrop, Command, x, y)
		end

		-- This panel is only meant to be copied from, not edited!
		if self:GetReadOnly() then
			return
		end

		local h = closest:GetTall()
		local w = closest:GetWide()

		local disty = y - (closest.y + h * 0.5)
		local distx = x - (closest.x + w * 0.5)

		local drop = 0
		if self.bDropCenter then
			drop = 5
		end

		if disty < 0 and self.bDropTop and (drop == 0 or math.abs(disty) > h * 0.1) then
			drop = 8
		end
		if disty >= 0 and self.bDropBottom and (drop == 0 or math.abs(disty) > h * 0.1) then
			drop = 2
		end
		if distx < 0 and self.bDropLeft and (drop == 0 or math.abs(distx) > w * 0.1) then
			drop = 4
		end
		if distx >= 0 and self.bDropRight and (drop == 0 or math.abs(distx) > w * 0.1) then
			drop = 6
		end

		self:UpdateDropTarget(drop, closest)

		if table.HasValue(Drops, closest) then
			return
		end

		if not bDoDrop and not self:GetUseLiveDrag() then
			return
		end

		-- This keeps the drop order the same,
		-- whether we add it before an object or after
		if drop == 6 or drop == 2 then
			Drops = table.Reverse(Drops)
		end

		for k, v in pairs(Drops) do
			-- Don't drop one of our parents onto us
			-- because we'll be sucked into a vortex
			if v:IsOurChild(self) then
				continue
			end
			if not v.Header then
				v = v:GetParent()
			end

			-- Copy the panel if we are told to from the DermaMenu(), or if we are moving from a read only panel to a not read only one.
			if
				(
					Command and Command == "copy"
					or (
						IsValid(v:GetParent())
						and v:GetParent().GetReadOnly
						and v:GetParent():GetReadOnly()
						and v:GetParent():GetReadOnly() ~= self:GetReadOnly()
					)
				) and v.Copy
			then
				v = v:Copy()
			end

			v = v:OnDrop(self, closest, drop == 2)

			if drop == 5 then
				closest:DroppedOn(v)
			end

			if drop == 8 or drop == 4 then
				v:SetParent(self)
				v:MoveToBefore(closest)
			end

			if drop == 2 or drop == 6 then
				v:SetParent(self)
				v:MoveToAfter(closest)
			end
		end

		-- self:OnModified()
	end

	listLayout:MakeDroppable(MGR.DnDTag, false)

	---@param child DForm
	function listLayout:OnChildAdded(child)
		child:Dock(TOP)

		local dn = self:GetDnD()
		if dn then
			child:Droppable(self:GetDnD())
			if child.Header then
				child.Header:Droppable(self:GetDnD())
			end
		end

		if self:IsSelectionCanvas() then
			child:SetSelectable(true)
		end
	end
end

---@param numpad RGPNumPad
---@param action InputAction
local function numpadHooks(numpad, action, keyChangedCallback)
	---@class RGPNumPad: DBinder

	local oldClick = numpad.DoClick
	function numpad:DoClick()
		local oldKey = self:GetValue()
		RagdollPoser.Input:UnregisterKey(action, oldKey)
		oldClick(self)
	end

	-- --- FIXME: Really buggy key bind handling
	-- function numpad:DoMiddleClick()
	-- 	local oldKey = self:GetValue()
	-- 	local default = self:GetDefaultNumber()
	-- 	RagdollPoser.Input:UnregisterKey(action, oldKey)
	-- 	---@diagnostic disable-next-line
	-- 	self:ResetToDefaultValue()
	-- 	RagdollPoser.Input:RegisterKey(action, default)
	-- end

	-- --- TODO: Implement key clearing in case one wants to clear their key binds
	-- function numpad:DoRightClick() end

	function numpad:OnChange(newKey)
		RagdollPoser.Input:RegisterKey(action, newKey)
		if keyChangedCallback then
			keyChangedCallback(newKey)
		end
	end
end

---@param cpanel ControlPanel
---@param leftProps KeyBinderProps
---@param rightProps KeyBinderProps?
---@return CtrlNumPad
local function keyBinder(cpanel, leftProps, rightProps)
	local binder
	if rightProps then
		binder = cpanel:KeyBinder(leftProps.label, leftProps.cvar, rightProps.label, rightProps.cvar)
	else
		binder = cpanel:KeyBinder(leftProps.label, leftProps.cvar)
	end

	numpadHooks(binder.NumPad1, leftProps.action, leftProps.keyChangedCallback)
	if rightProps then
		numpadHooks(binder.NumPad2, rightProps.action, rightProps.keyChangedCallback)
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
	entry:SetList(parent.List)
	parent.List:Add(entry)
	parent.Items[index] = entry
	entry.constraint = constraint
	function entry.Header:DoRightClick()
		local menu = DermaMenu()

		menu:AddOption("#tool.ragdollposer.constraint.remove", function()
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

	entry.Header.UpdateColours = function(self, skin)
		if self:GetParent() and not self:GetParent():GetExpanded() then
			self:SetExpensiveShadow(0, Color(0, 0, 0, 200))
			return self:SetTextStyleColor(skin.Colours.Category.Header_Closed)
		end

		self:SetExpensiveShadow(1, Color(0, 0, 0, 100))
		return self:SetTextStyleColor(skin.Colours.Category.Header)
	end

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

	function entry:ValidateArrows(index, count)
		self.up:SetEnabled(index > 1)
		self.down:SetEnabled(index < count)
	end

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

			previousEntry:ValidateArrows(index, #stack)
			entry:ValidateArrows(newIndex, #stack)
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

			nextEntry:ValidateArrows(index, #stack)
			entry:ValidateArrows(newIndex, #stack)
		end
	end

	---@param pnl DListLayout
	---@param closest ConstraintEntry
	---@param isBelow boolean
	function entry:OnDrop(pnl, closest, isBelow)
		if closest then
			local myIndex = RagdollPoser.Constraints:GetConstraintIndex(entity, constraint._id)
			local stack = RagdollPoser.Constraints:GetConstraintStack(entity)

			table.remove(parent.Items, myIndex)
			RagdollPoser.Constraints:MoveTo(entity, constraint, closest.constraint, isBelow)
			local myNewIndex = RagdollPoser.Constraints:GetConstraintIndex(entity, constraint._id)
			table.insert(parent.Items, myNewIndex, self)

			for i, item in ipairs(parent.Items) do
				item:ValidateArrows(i, #stack)
			end
		end

		return self
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

	entry.keybinder = keyBinder(entry, {
		label = "#tool.ragdollposer.constraint.bind",
		cvar = "",
		action = RagdollPoser.Actions.ToggleConstraint,
		keyChangedCallback = function(newKey)
			constraint.State.key = newKey
			-- print("run this!", constraint.State.key)
			RagdollPoser.Constraints:UpdateConstraint(entity, constraint)
		end,
	})

	if constraint.State.key > -1 then
		entry.keybinder.NumPad1:SetValue(constraint.State.key)
	end

	entry:SetExpanded(false)

	return entry
end

local mirrorMapping = {
	[0] = "x",
	[1] = "y",
	[2] = "z",
}
local mirrorMappingInverse = table.Flip(mirrorMapping)

--- Preserve the old position of the scroll when clearing up things, for consistency
---@param tree rgp_tree
local function preserveScroll(tree)
	local oldVScroll, oldHScroll = tree.VBar:GetScroll(), tree.HBar:GetScroll()
	return function()
		tree.VBar:SetScroll(oldVScroll)
		tree.HBar:SetScroll(oldHScroll)
	end
end

---@param entityTree EntityTree
---@param clients ClientEntity[]
---@param selectedEntities SelectedEntities
local function populateEntities(entityTree, clients, selectedEntities)
	local preserve = preserveScroll(entityTree)
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
		local entity = RagdollPoser.Entity:GetEntityFromClient(client)
		local childNode = entityTree[client]
		local parentClient = RagdollPoser.Entity:GetClientFromEntity(entity:GetParent())
		local parentNode = IsValid(parentClient) and entityTree[parentClient]
		if parentNode then
			parentNode:CreateChildNodes()
			childNode:SetParentNode(parentNode)
			---@diagnostic disable-next-line: unchecked-nil-access, undefined-field
			parentNode.ChildNodes:Add(childNode)
			parentNode:InvalidateLayout()
			parentNode:SetExpanded(true, true)
		end
	end
	preserve()
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
---@field bone integer
---@field boneType BoneType

---@class BoneTreeRoot: DTree
---@field nodes table<integer, BoneTreeNode>

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

	function child:TestHover()
		hook.Run("RagdollPoser_Selection_Hover", bone, entity)
	end

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

	function child:DoRightClick()
		MGR:ContextMenu(entity, bone)
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
---@param boneTree BoneTreeRoot
---@param boneTypeRestriction BoneType|boolean
local function setupBoneNodesOf(entity, boneTree, boneTypeRestriction)
	---@type table<integer, BoneTreeNode>
	boneTree.nodes = {}
	local parentSet = {}
	for b = 0, entity:GetBoneCount() - 1 do
		if entity:GetBoneName(b) == "__INVALIDBONE__" then
			continue
		end

		RagdollPoser.Entity:ExposeBones(entity)

		local boneType = getBoneType(entity, b)
		if boneTypeRestriction and boneType ~= boneTypeRestriction then
			continue
		end

		local parent = entity:GetBoneParent(b)
		if parent > -1 and parentSet[parent] then
			local node = addBoneNode(parentSet[parent], entity, b, entity:GetBoneName(b), boneType)
			parentSet[b] = node
			parentSet[b].boneId = b
			parentSet[b].boneType = boneType
		else
			local node = addBoneNode(boneTree, entity, b, entity:GetBoneName(b), boneType)
			parentSet[b] = node
			parentSet[b].boneId = b
			parentSet[b].boneType = boneType
		end
	end
	boneTree.nodes = parentSet
end

---@param boneTree BoneTree
---@param selection Selection
---@param boneTypeRestriction BoneType|boolean
local function populateBoneTree(boneTree, selection, boneTypeRestriction)
	local preserve = preserveScroll(boneTree)
	boneTree:Clear()
	---@type table<ClientEntity, BoneTreeRoot>
	boneTree.Entities = {}

	for i = 1, #selection - 1, 2 do
		local bone = selection[i] --[[@as integer]]
		local entity = selection[i + 1] --[[@as ClientEntity]]

		local boneRoot = boneTree.Entities[entity]
		if not boneTree.Entities[entity] then
			---@class BoneTreeRoot
			boneRoot = boneTree:AddNode(getNiceModelName(entity), getModelIcon(entity)) --[[@as DTree]]
			boneRoot:SetExpanded(true)
			setupBoneNodesOf(entity, boneRoot, boneTypeRestriction)
			boneTree.Entities[entity] = boneRoot
		end

		local selectedNode = boneRoot.nodes[bone]
		if selectedNode then
			selectedNode:SetSelected(true)
		end
	end
	preserve()
end

local function updateBoneTree(boneTree, selection, boneTypeRestriction)
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
			setupBoneNodesOf(entity, boneRoot, boneTypeRestriction)
			boneTree.Entities[entity] = boneRoot
		end

		selected[entity] = true
		local selectedNode = boneRoot.nodes[bone]
		if selectedNode then
			selectedNode:SetSelected(true)
		end
	end

	for entity, node in pairs(boneTree.Entities) do
		if not selected[entity] then
			node:Remove()
			boneTree.Entities[entity] = nil
		end
	end
end

---@param menu DMenu
function MGR:OffsetMenu(menu, yOffset)
	local x, y = input.GetCursorPos()
	menu:Open(x, y)
	-- Open it twice. Why? So that we can offset it when the internals performs all the positioning
	local w, h = menu:GetSize()
	x = math.min(x, ScrW()) - w * 0.99
	if yOffset then
		y = math.min(y, ScrH()) - yOffset * 1.05
	end
	menu:Open(x, y)
end

--- @param client ClientEntity
--- @param bone integer?
--- @param keepOpen boolean?
--- @param parentMenu DMenu?
function MGR:GizmoMenu(client, bone, keepOpen, parentMenu)
	local menu
	if parentMenu then
		menu = parentMenu:AddSubMenu("#tool.ragdollposer.gizmo", function() end)
	else
		menu = DermaMenu(keepOpen)
	end

	menu:AddOption("#tool.ragdollposer.gizmo.offset.set", function()
		local pos = RagdollPoser.Gizmo:GetPosition()
		local ang = RagdollPoser.Gizmo:GetAngles()
		local m = client:GetBoneMatrix(bone)
		if m then
			local offset = WorldToLocal(m:GetTranslation(), angle_zero, pos, ang)
			RagdollPoser.Gizmo:SetOffset(offset[1], offset[2], offset[3])
		end
	end)
	menu:AddOption("#tool.ragdollposer.gizmo.offset.reset", function()
		RagdollPoser.Gizmo:SetOffset(0, 0, 0)
	end)
end

--- Show options for resetting transforms
--- @param client ClientEntity
--- @param bone integer?
--- @param keepOpen boolean?
--- @param parentMenu DMenu?
function MGR:ResetMenu(client, bone, keepOpen, parentMenu)
	local menu
	if parentMenu then
		menu = parentMenu:AddSubMenu("#tool.ragdollposer.reset", function() end)
	else
		menu = DermaMenu(keepOpen)
	end

	menu:AddOption("#tool.ragdollposer.all", function()
		-- TODO: Implement reset all
		-- RagdollPoser.Gizmo:ResetSelected(4, bone, client)
	end)
	menu:AddOption("#tool.ragdollposer.pos", function()
		RagdollPoser.Gizmo:ResetSelected(RagdollPoser.Gizmo.Mode.Translation, bone, client)
	end)
	menu:AddOption("#tool.ragdollposer.ang", function()
		RagdollPoser.Gizmo:ResetSelected(RagdollPoser.Gizmo.Mode.Rotation, bone, client)
	end)
	menu:AddOption("#tool.ragdollposer.scale", function()
		RagdollPoser.Gizmo:ResetSelected(RagdollPoser.Gizmo.Mode.Scale, bone, client)
	end)

	if not parentMenu then
		menu:Open()
	end
end

--- Show options for manipulating bones
--- @param client ClientEntity
--- @param bone integer?
--- @param keepOpen boolean?
--- @param parentMenu DMenu?
function MGR:BoneMenu(client, bone, keepOpen, parentMenu)
	local menu
	if parentMenu then
		menu = parentMenu:AddSubMenu("#tool.ragdollposer.bone", function() end)
	else
		menu = DermaMenu(keepOpen)
	end

	menu:AddOption("#tool.ragdollposer.bone.scale.zero", function()
		RagdollPoser.Gizmo:ScaleZero(bone, client)
	end)
	menu:AddOption("#tool.ragdollposer.bone.scale.zero.children", function()
		-- TODO: Implement recursive children operation in Gizmo
	end)
	menu:AddOption("#tool.ragdollposer.bone.copy", function()
		RagdollPoser.Entity:ExposeBones(client)
		SetClipboardText(client:GetBoneName(bone))
	end)

	if not parentMenu then
		menu:Open()
	end
end

--- @param client ClientEntity
--- @param bone integer?
--- @param keepOpen boolean?
--- @param parentMenu DMenu?
function MGR:ConstraintMenu(client, bone, keepOpen, parentMenu)
	local entity = RagdollPoser.Entity:GetEntityFromClient(client)

	-- get list of constraints categories, then insert each constraint in a category
	-- click on a constraint name. we add the constraint to the entity. also send it to the server
	-- so that when we reselect entities, we also get constraint info
	-- get the constraint info, and make constraint entry based off actual constraints that exist there
	local menu
	if parentMenu then
		menu = parentMenu:AddSubMenu("#tool.ragdollposer.constraint")
	else
		menu = DermaMenu(keepOpen)
	end

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
		table.sort(constraints, function(a, b)
			---@cast a Constraint
			---@cast b Constraint
			local nameA = language.GetPhrase(a.Properties.name)
			local nameB = language.GetPhrase(b.Properties.name)
			return nameA < nameB
		end)
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
					name = Format("%s: %s", language.GetPhrase(constraint.Properties.short), entity:GetBoneName(bone))
				end
				---@diagnostic disable-next-line: param-type-mismatch
				RagdollPoser.Constraints:Push(entity, constraint.Properties.type, state, name)
			end)
			option:SetTooltip(language.GetPhrase(constraint.Properties.desc))
		end
	end

	if not parentMenu then
		menu:Open()
	end
end

function MGR:ContextMenu(entity, bone, keepOpen)
	-- TODO: Why does this become invalid all of a sudden?
	if not IsValid(entity) then
		return
	end

	gui.EnableScreenClicker(true)
	local menu = DermaMenu(keepOpen)
	---@diagnostic disable-next-line: redundant-parameter
	local option = menu:AddOption(language.FormatPhrase("#tool.ragdollposer.context.title", entity:GetBoneName(bone)))
	option:SetEnabled(false)
	menu:AddSpacer()
	RagdollPoser.UI:GizmoMenu(entity, bone, keepOpen, menu)
	RagdollPoser.UI:ConstraintMenu(entity, bone, keepOpen, menu)
	RagdollPoser.UI:BoneMenu(entity, bone, keepOpen, menu)
	RagdollPoser.UI:ResetMenu(entity, bone, keepOpen, menu)
	menu:Open()
	self:OffsetMenu(menu, option:GetTall())

	function menu:OnRemove()
		RagdollPoser.Gizmo:SetEnabled(true)
		RagdollPoser.Selection:SetEnabled(false)
		gui.EnableScreenClicker(false)
	end
end

local filteredPanels = {
	GModBasePanel = true,
	[""] = true, -- This is just a representation of "I'm not hovering over anything"
	ContextMenu = true,
	DNotify = true,
}

function MGR:IsHoveringWorld()
	local hoveredPanel = vgui.GetHoveredPanel()
	local parentPanel = hoveredPanel and hoveredPanel:GetParent()
	local hoveredClass = hoveredPanel and hoveredPanel:GetName() or ""
	local parentClass = parentPanel and parentPanel:GetName() or ""
	-- Only allow input when we're hovering over nothing or on the panels shown above
	return filteredPanels[hoveredClass] or filteredPanels[parentClass]
end

---These delta setter/getters are used by the precise bone manip
---sliders to communicate slider deltas to the gizmos
---@param delta number
function MGR:SetDelta(delta)
	self.delta = delta
end

---@return number
function MGR:GetDelta()
	return self.delta
end

local batch = false
local function onGizmoChange(sliders)
	if batch then
		return
	end
	RagdollPoser.Gizmo:SetOffset(sliders[1]:GetValue(), sliders[2]:GetValue(), sliders[3]:GetValue())
end

local function gizmoOffsetHooks(slider, key, sliders)
	local offset = RagdollPoser.Gizmo:GetOffset()
	slider:SetDefaultValue(0)

	slider:SetValue(offset[key])

	slider.OnValueChanged = function()
		onGizmoChange(sliders)
	end
end

---@param entity ClientEntity
---@param bone integer
---@param sliderType GizmoMode
local function convertTransformToStr(entity, bone, sliderType)
	local matrix = entity:GetBoneMatrix(bone)
	local transform
	if sliderType == RagdollPoser.Gizmo.Mode.Translation then
		transform = matrix:GetTranslation()
	elseif sliderType == RagdollPoser.Gizmo.Mode.Rotation then
		transform = matrix:GetAngles()
	elseif sliderType == RagdollPoser.Gizmo.Mode.Scale then
		transform = matrix:GetScale()
	end
	return Format("%.3f %.3f %.3f", transform[1], transform[2], transform[3])
end

local directions = { "X", "Y", "Z" }
---@alias DeltaCallback fun(x: number, y: number, z: number)

---@param cPanel ControlPanel
---@param sliderType GizmoMode
---@param valueChanged DeltaCallback?
local function transformSliders(cPanel, sliderType, valueChanged)
	local sliders = {}
	for i = 1, 3 do
		local slider = cPanel:NumSlider(directions[i], "", -100, 100, 3)
		slider:SetDefaultValue(0)
		slider:SetValue(0)

		function slider:OnValueChanged()
			if self.resetDelta then
				return
			end

			if valueChanged then
				valueChanged(sliders[1]:GetValue(), sliders[2]:GetValue(), sliders[3]:GetValue())
			end
		end

		local lastEdit
		local lastMode
		local lastOrientation
		local oldValue = slider:GetValue()
		function slider:Think()
			local currentValue = slider:GetValue()
			local editing = self:IsEditing()
			if editing and not lastEdit then
				oldValue = slider:GetValue()

				lastMode = RagdollPoser.Gizmo:GetMode()
				lastOrientation = RagdollPoser.Gizmo:GetOrientation()
				RagdollPoser.Gizmo:SetOrientation(RagdollPoser.Gizmo.Orientation.Local)
				RagdollPoser.Gizmo:OnModeChanged(sliderType)
				RagdollPoser.Gizmo._gizmoIndex = i

				-- Let's move shit
				RagdollPoser.Gizmo:SetMovingUI(true)
				RagdollPoser.Gizmo:SetMoving(true)
				RagdollPoser.Gizmo:PreTransform()
			elseif not editing and lastEdit then
				-- We're done!
				RagdollPoser.Gizmo:SetMoving(false)
				RagdollPoser.Gizmo:SetMovingUI(false)
				RagdollPoser.Gizmo:PostTransform()
				self.resetDelta = true
				self:SetValue(0)
				self.resetDelta = false

				RagdollPoser.Gizmo:SetOrientation(lastOrientation)
				RagdollPoser.Gizmo:OnModeChanged(lastMode)
			end
			if editing then
				MGR:SetDelta(currentValue - oldValue)
			end
			lastEdit = editing
			oldValue = currentValue
		end

		sliders[i] = slider
	end
	return sliders
end

---@param cPanel ControlPanel
---@param sliderType GizmoMode
---@param valueChanged DeltaCallback?
local function transformEntry(cPanel, sliderType, valueChanged)
	local entry = vgui.Create("DTextEntry", cPanel)
	entry:SetText("0 0 0")

	---TODO: Implement transform setting here
	local oldState = string.Split(entry:GetText(), " ")
	function entry:OnValueChange()
		if self.updating then
			return
		end

		local state = string.Split(entry:GetText(), " ")
		if valueChanged then
			valueChanged(tonumber(state[1]), tonumber(state[2]), tonumber(state[3]))
		end
	end

	function entry:SetTransform(text)
		text = text or "* * *"
		self.updating = true
		self:SetValue(text)
		self.updating = false
	end

	return entry
end

---@param MGR RagdollPoser.UI
local function openConstraintBrowser(MGR)
	if not MGR.ConstraintFrame then
		local w, h = ScrW() * 0.25, ScrH() * 0.25

		local dFrame = vgui.Create("DFrame")
		local fileBrowser = dFrame:Add("DFileBrowser")
		fileBrowser:Dock(FILL)
		fileBrowser:SetPath("DATA")
		fileBrowser:SetFileTypes("*.txt")
		fileBrowser:SetBaseFolder("ragdollposer/constraints")
		fileBrowser:SetCurrentFolder("ragdollposer/constraints")
		dFrame.FileBrowser = fileBrowser

		dFrame.ButtonLayout = dFrame:Add("DPanel")
		dFrame.ButtonLayout:Dock(BOTTOM)

		dFrame:SetSizable(true)

		local load, save = dFrame.ButtonLayout:Add("DButton"), dFrame.ButtonLayout:Add("DButton")
		save:SetText("#tool.ragdollposer.save")
		load:SetText("#tool.ragdollposer.load")

		local settingsContainer = dFrame:Add("DPanel")
		settingsContainer:Dock(RIGHT)
		settingsContainer:SetWide(w * 0.375)
		local settings = settingsContainer:Add("ControlPanel")
		settings:SetLabel("#tool.ragdollposer.settings")
		settings:Dock(FILL)
		local check = settings:CheckBox("#tool.ragdollposer.constraint.browser.target", "")
		-- By default, always target the selected entity
		check:SetChecked(true)
		dFrame.Settings = settings
		dFrame.Settings.Target = check

		local label = dFrame.ButtonLayout:Add("DTextEntry")
		label:Dock(RIGHT)
		label:DockMargin(0, 0, 2, 0)
		label:SetSize(w * 0.5, save:GetTall())
		dFrame.ButtonLayout.FileName = label

		local selectedPath = ""
		function fileBrowser:OnSelect(filePath, panel)
			selectedPath = filePath
			local tab = string.Split(selectedPath, "/")
			label:SetText(tab[#tab])
		end

		function label:OnChange()
			local currentPath = fileBrowser:GetCurrentFolder()
			selectedPath = currentPath .. "/" .. label:GetValue() .. ".txt"
		end

		local function loadCallback(success, errMsg)
			if not success then
				ErrorNoHalt("[Ragdoll Poser] Failed to load constraint preset: \n", errMsg)
			end
		end

		function load:DoClick()
			local selected = MGR.EntitySelector.selected
			if IsValid(selected) then
				local entity = RagdollPoser.Entity:GetEntityFromClient(selected)
				local result, msg = RagdollPoser.File:LoadConstraintPreset(entity, selectedPath,
					RagdollPoser.File.ConstraintLoadType.Replace,
					check:GetChecked(), loadCallback)
			end
		end

		function load:DoRightClick()
			local selected = MGR.EntitySelector.selected
			if IsValid(selected) then
				local entity = RagdollPoser.Entity:GetEntityFromClient(selected)
				local menu = DermaMenu()
				menu:AddOption("#tool.ragdollposer.constraint.browser.replace", function()
					RagdollPoser.File:LoadConstraintPreset(entity, selectedPath,
						RagdollPoser.File.ConstraintLoadType.Replace,
						check:GetChecked(), loadCallback)
				end)
				-- TODO: Figure ouot how to handle inserting constraint entries at arbitrary positions
				-- menu:AddOption("#tool.ragdollposer.constraint.browser.prepend", function()
				-- 	RagdollPoser.File:LoadConstraintPreset(entity, selectedPath,
				-- 		RagdollPoser.File.ConstraintLoadType.Prepend,
				-- 		check:GetChecked(), loadCallback)
				-- end)
				menu:AddOption("#tool.ragdollposer.constraint.browser.append", function()
					RagdollPoser.File:LoadConstraintPreset(entity, selectedPath,
						RagdollPoser.File.ConstraintLoadType.Append,
						check:GetChecked(), loadCallback)
				end)
				menu:Open()
			end
		end

		function save:DoClick()
			local currentPath = fileBrowser:GetCurrentFolder()
			local files = file.Find(string.Trim(currentPath .. "/" .. (fileBrowser:GetFileTypes()), "/"), "DATA")
			local currentFile = label:GetValue()
			local displayWarning = false
			for _, file in ipairs(files) do
				if file == currentFile then
					displayWarning = true
					break
				end
			end

			local function doSave()
				local selected = MGR.EntitySelector.selected
				if IsValid(selected) then
					local entity = RagdollPoser.Entity:GetEntityFromClient(selected)
					local constraints = RagdollPoser.Constraints:GetConstraintStack(entity)
					local result, msg = RagdollPoser.File:SaveConstraintPreset(constraints, selectedPath)
				end
			end

			if displayWarning then
				Derma_Query(
					language.FormatPhrase("#tool.ragdollposer.constraint.save.warning", currentFile),
					"#tool.ragdollposer.warning",
					"#tool.ragdollposer.save", doSave,
					"#tool.ragdollposer.cancel")
			else
				doSave()
			end
		end

		load:Dock(RIGHT)
		load:DockMargin(0, 0, 2, 0)
		save:Dock(RIGHT)
		save:DockMargin(0, 0, 2, 0)

		dFrame.ButtonLayout.Load = load
		dFrame.ButtonLayout.Save = save

		dFrame.ButtonLayout:SetTall(save:GetTall())

		dFrame:SetSize(w, h)
		dFrame:SetPos(w * 1.5, h * 1.5)

		-- For debugging purpose, set this to true
		dFrame:SetDeleteOnClose(false)

		local oldLayout = dFrame.PerformLayout
		function dFrame:PerformLayout(width, height)
			oldLayout(self)
			self.ButtonLayout.FileName:SetWide(width * 0.5)
		end

		MGR.ConstraintFrame = dFrame
	end

	if IsValid(MGR.ConstraintFrame.FileBrowser) then
		MGR.ConstraintFrame.FileBrowser:SetCurrentFolder(MGR.ConstraintFrame.FileBrowser:GetCurrentFolder())
	end
	MGR.ConstraintFrame:SetVisible(true)
	MGR.ConstraintFrame:MakePopup()
end

---@param cpanel ControlPanel
function MGR:BuildCPanel(cpanel)
	local gizmoCategory = makeCategory(cpanel, language.GetPhrase("#tool.ragdollposer.gizmo"), "ControlPanel")
	gizmoCategory:CheckBox("#tool.ragdollposer.local", "ragdollposer_local")
	gizmoCategory
		:CheckBox("#tool.ragdollposer.partial", "ragdollposer_partial")
		:SetTooltip("#tool.ragdollposer.partial.tooltip")
	local drawSphere = gizmoCategory:CheckBox("#tool.ragdollposer.gizmo.drawsphere", "ragdollposer_drawsphere")
	local scaleSlider = gizmoCategory:NumSlider("#tool.ragdollposer.scale", "ragdollposer_scale", 0.1, 50, 2)
	local widthSlider = gizmoCategory:NumSlider("#tool.ragdollposer.width", "ragdollposer_width", 0.1, 1, 2)

	local cycleAndSurface = keyBinder(gizmoCategory, {
		label = "#tool.ragdollposer.cycle",
		cvar = "ragdollposer_cycle_key",
		action = RagdollPoser.Actions.CycleGizmo,
	}, {
		label = "#tool.ragdollposer.surface",
		cvar = "ragdollposer_surface_key",
		action = RagdollPoser.Actions.AttachSurface,
	})

	local precise = keyBinder(gizmoCategory, {
		label = "#tool.ragdollposer.precise",
		cvar = "ragdollposer_precision_key",
		action = RagdollPoser.Actions.DoPrecision,
	})

	local gizmoOffsets =
		makeCategory(gizmoCategory, language.GetPhrase("#tool.ragdollposer.gizmo.offset"), "ControlPanel")

	gizmoOffsets:CheckBox("#tool.ragdollposer.gizmo.localoffset", "ragdollposer_localoffset")
	gizmoOffsets:CheckBox("#tool.ragdollposer.gizmo.relativerotate", "ragdollposer_relativerotate")

	-- this gizmo offset construction is uuuuuuuuuuuuuuuuuuuuuugly!
	local x = gizmoOffsets:NumSlider("#tool.ragdollposer.gizmo.offset.x", "", -100, 100, 3)
	local y = gizmoOffsets:NumSlider("#tool.ragdollposer.gizmo.offset.y", "", -100, 100, 3)
	local z = gizmoOffsets:NumSlider("#tool.ragdollposer.gizmo.offset.z", "", -100, 100, 3)
	local sliders = { x, y, z }
	gizmoOffsetHooks(x, "x", sliders)
	gizmoOffsetHooks(y, "y", sliders)
	gizmoOffsetHooks(z, "z", sliders)

	local resetOffsets = gizmoOffsets:Button("#tool.ragdollposer.gizmo.offset.reset", "")
	function resetOffsets:DoClick()
		batch = true
		x:SetValue(0)
		y:SetValue(0)
		z:SetValue(0)
		batch = false
		onGizmoChange(sliders)
	end

	gizmoOffsets:SetExpanded(false)

	local function offsetChanged(offset)
		batch = true
		x:SetValue(offset.x)
		y:SetValue(offset.y)
		z:SetValue(offset.z)
		batch = false
	end
	hook.Add("RagdollPoser_Gizmo_OffsetChanged", "UI", offsetChanged)

	local misc = makeCategory(cpanel, language.GetPhrase("tool.ragdollposer.misc"), "ControlPanel")
	local selection = misc:CheckBox("#tool.ragdollposer.selection", "ragdollposer_selection")
	selection:SetTooltip("#tool.ragdollposer.selection.tooltip")
	local skeleton = misc:CheckBox("#tool.ragdollposer.skeleton", "ragdollposer_skeleton")
	skeleton:SetTooltip("#tool.ragdollposer.skeleton.tooltip")
	local drawSelected = misc:CheckBox("#tool.ragdollposer.drawselected", "ragdollposer_drawselected")
	drawSelected:SetTooltip("#tool.ragdollposer.drawselected.tooltip")
	local static = misc:CheckBox("#tool.ragdollposer.static", "ragdollposer_static")
	static:SetTooltip("#tool.ragdollposer.static.tooltip")
	local xray = misc:CheckBox("#tool.ragdollposer.xray", "ragdollposer_xray")
	xray:SetTooltip("#tool.ragdollposer.xray.tooltip")
	local xraySelection = misc:CheckBox("#tool.ragdollposer.xray.selection", "ragdollposer_xray_selection")
	xraySelection:SetTooltip("#tool.ragdollposer.xray.selection.tooltip")
	local subtitle = misc:CheckBox("#tool.ragdollposer.misc.funsubtitles", "ragdollposer_funsubtitles")
	subtitle:SetTooltip("#tool.ragdollposer.misc.funsubtitles.tooltip")

	local boneManip = makeCategory(cpanel, language.GetPhrase("tool.ragdollposer.bone.manip"), "ControlPanel")

	-- TODO: Compress this cheeseburger of a UI (maybe put related transforms in a function, keyed by Gizmo mode?)
	local entryDock = 10
	local preciseBoneManip =
		makeCategory(boneManip, language.GetPhrase("tool.ragdollposer.bone.precise"), "ControlPanel")
	-- These are displacements, not world position sliders. If exacts are needed, then the entry can be used
	local positionReset = preciseBoneManip:Button("#tool.ragdollposer.bone.precise.pos.reset")
	local positionEntry = transformEntry(preciseBoneManip, RagdollPoser.Gizmo.Mode.Translation)
	preciseBoneManip:AddItem(positionEntry, positionReset)
	positionEntry:Dock(FILL)
	positionReset:Dock(RIGHT)
	positionReset:DockMargin(entryDock, 0, 0, 0)
	local positionSliders = transformSliders(preciseBoneManip, RagdollPoser.Gizmo.Mode.Translation)
	function positionReset:DoClick()
		RagdollPoser.Gizmo:ResetSelected(RagdollPoser.Gizmo.Mode.Translation)
	end

	local rotationReset = preciseBoneManip:Button("#tool.ragdollposer.bone.precise.ang.reset")
	local rotationEntry = transformEntry(preciseBoneManip, RagdollPoser.Gizmo.Mode.Rotation)
	preciseBoneManip:AddItem(rotationEntry, rotationReset)
	rotationEntry:Dock(FILL)
	rotationReset:Dock(RIGHT)
	rotationReset:DockMargin(entryDock, 0, 0, 0)
	local rotationSliders = transformSliders(preciseBoneManip, RagdollPoser.Gizmo.Mode.Rotation)
	function rotationReset:DoClick()
		RagdollPoser.Gizmo:ResetSelected(RagdollPoser.Gizmo.Mode.Rotation)
	end

	local scaleReset = preciseBoneManip:Button("#tool.ragdollposer.bone.precise.scale.reset")
	local scaleEntry = transformEntry(preciseBoneManip, RagdollPoser.Gizmo.Mode.Scale)
	preciseBoneManip:AddItem(scaleEntry, scaleReset)
	scaleEntry:Dock(FILL)
	scaleReset:Dock(RIGHT)
	scaleReset:DockMargin(entryDock, 0, 0, 0)
	function scaleReset:DoClick()
		RagdollPoser.Gizmo:ResetSelected(RagdollPoser.Gizmo.Mode.Scale)
	end

	local scaleSliders = transformSliders(preciseBoneManip, RagdollPoser.Gizmo.Mode.Scale)

	preciseBoneManip:SetExpanded(false)

	boneManip:CheckBox("#tool.ragdollposer.mirror", "ragdollposer_mirror")
	local mirrorCombo = boneManip:ComboBox("#tool.ragdollposer.mirror.axis", "ragdollposer_mirror_axis")
	mirrorCombo:AddChoice("x", 0)
	mirrorCombo:AddChoice("y", 1)
	mirrorCombo:AddChoice("z", 2)
	local id = GetConVar("ragdollposer_mirror_axis"):GetInt() + 1
	mirrorCombo:ChooseOption(mirrorMapping[id - 1], id)

	local snapEnable = boneManip:CheckBox("#tool.ragdollposer.snap", "ragdollposer_snap")
	snapEnable:SetTooltip("#tool.ragdollposer.snap")
	local snapValue = boneManip:NumSlider("#tool.ragdollposer.snap.value", "ragdollposer_snap_value", 0, 180, 3)
	local snapWide, snapTall = snapValue:GetSize()
	snapValue:SizeTo(-1, snapEnable:GetChecked() and snapTall or 0, 0.1)
	function snapEnable:OnChange(newValue)
		snapValue:SizeTo(-1, newValue and snapTall or 0, 0.1)
	end

	self.snapValue = snapValue

	local selectBoneAndRoot = keyBinder(boneManip, {
		label = "#tool.ragdollposer.select.toggle",
		cvar = "ragdollposer_select_key",
		action = RagdollPoser.Actions.SelectBone,
	}, {
		label = "#tool.ragdollposer.select.root",
		cvar = "ragdollposer_select_root_key",
		action = RagdollPoser.Actions.SelectRoot,
	})

	local boneTreeCategory = makeCategory(boneManip, language.GetPhrase("tool.ragdollposer.bone.tree"), "ControlPanel")

	local buttonContainer = boneTreeCategory:Add("DSizeToContents")
	local phys, all, nonPhys =
		buttonContainer:Add("DButton"), buttonContainer:Add("DButton"), buttonContainer:Add("DButton")
	phys:Dock(LEFT)
	all:Dock(FILL)
	nonPhys:Dock(RIGHT)
	phys:SetText("#tool.ragdollposer.bone.phys")
	all:SetText("#tool.ragdollposer.bone.all")
	nonPhys:SetText("#tool.ragdollposer.bone.nonphys")
	buttonContainer:SetTall(25)

	-- Notify other systems to show or hide certain bones
	function phys.DoClick()
		hook.Run("RagdollPoser_UI_Bone_Show", self.BoneCategory.Phys)
	end

	function all.DoClick()
		hook.Run("RagdollPoser_UI_Bone_Show", self.BoneCategory.All)
	end

	function nonPhys.DoClick()
		hook.Run("RagdollPoser_UI_Bone_Show", self.BoneCategory.NonPhys)
	end

	local panelContainer = vgui.Create("DPanel", boneTreeCategory)
	panelContainer:SizeTo(-1, 600, 0)
	boneTreeCategory:AddItem(panelContainer)
	local boneTreeContainer = vgui.Create("DPanel", panelContainer)
	local drawer = vgui.Create("rgp_dhdrawer", panelContainer)
	drawer.ToggleButton:SetTooltip("#tool.ragdollposer.entity.selector.tooltip")
	local entitySelectorContainer = vgui.Create("DPanel", drawer)
	entitySelectorContainer:Dock(FILL)
	boneTreeContainer:Dock(FILL)
	drawer:Open()
	drawer:Close()

	---@class EntityTree: rgp_tree
	---@field [ClientEntity] DTree_Node
	---@field selected ClientEntity
	local entitySelector = entitySelectorContainer:Add("rgp_tree")
	self.EntitySelector = entitySelector

	---@class BoneTree: rgp_tree
	---@field [ClientEntity] DTree_Node
	local boneTree = boneTreeContainer:Add("rgp_tree")

	entitySelector:Dock(FILL)
	boneTree:Dock(FILL)

	populateEntities(
		entitySelector,
		RagdollPoser.Entity:GetClientEntities(),
		RagdollPoser.Selection:GetSelectedEntities()
	)
	populateBoneTree(boneTree, RagdollPoser.Selection:GetSelection(), false)

	local constraintCategory = makeCategory(cpanel, language.GetPhrase("tool.ragdollposer.constraint"), "ControlPanel")
	local addConstraint = constraintCategory:Button(language.GetPhrase("tool.ragdollposer.constraint.add"))
	local openConstraint = constraintCategory:Button(language.GetPhrase("tool.ragdollposer.constraint.open"))
	constraintCategory:AddItem(addConstraint, openConstraint)
	local clearConstraints = constraintCategory:Button(language.GetPhrase("tool.ragdollposer.constraint.clear"))

	local constraintListForm =
		makeCategory(constraintCategory, language.GetPhrase("tool.ragdollposer.constraint.list"), "DForm")
	local constraintListContainer = vgui.Create("DPanel", constraintListForm)
	constraintListForm:AddItem(constraintListContainer)
	constraintListContainer:SizeTo(-1, 200, 0)
	---@class ConstraintForm: DCategoryList
	---@field Items ConstraintEntry[]
	---@field List DListLayout
	local constraintList = vgui.Create("DCategoryList", constraintListContainer)
	constraintList:Dock(FILL)
	constraintList.List = vgui.Create("DListLayout", constraintList)
	constraintList.List:Dock(FILL)
	constraintList.Items = {}
	-- print("constraint list items!")
	-- print(constraintList.Items)

	local function setEnabledConstraintButtons()
		local enable = IsValid(entitySelector.selected)
		addConstraint:SetEnabled(enable)
		openConstraint:SetEnabled(enable)
		clearConstraints:SetEnabled(enable)
	end
	setEnabledConstraintButtons()

	function addConstraint:DoClick()
		if IsValid(entitySelector.selected) then
			MGR:ConstraintMenu(entitySelector.selected)
		end
	end

	function openConstraint:DoClick()
		openConstraintBrowser(MGR)
	end

	local function clearConstraintsUI()
		local oldScroll = constraintList:GetVBar():GetScroll()
		constraintList:Clear()
		constraintList.List = vgui.Create("DListLayout", constraintList)
		constraintListHook(constraintList.List)
		return function()
			constraintList:GetVBar():AnimateTo(oldScroll, 0.1, 0, 0)
		end
	end

	function clearConstraints:DoClick()
		local selected = RagdollPoser.Entity:GetEntityFromClient(entitySelector.selected)
		if IsValid(selected) then
			local menu = DermaMenu()
			menu:AddOption(language.GetPhrase("#tool.ragdollposer.constraint.clear.confirm"), function()
				selected = RagdollPoser.Entity:GetEntityFromClient(entitySelector.selected)
				clearConstraintsUI()

				RagdollPoser.Constraints:Clear(selected)
			end)
			menu:Open()
		end
	end

	--- @param client ClientEntity
	local function updateConstraintUI(client)
		local entity = RagdollPoser.Entity:GetEntityFromClient(client)
		-- constraintList.List:Dock(FILL)
		local restoreScroll = clearConstraintsUI()
		local constraints = RagdollPoser.Constraints:GetConstraintStack(entity)
		if constraints then
			for _, constraint in ipairs(constraints) do
				makeConstraintEntry(constraintList, entity, constraint)
			end
		end
		restoreScroll()
	end

	---@param client ClientEntity
	function entitySelector:EntitySelected(client)
		updateConstraintUI(client)
	end

	-- Listen to system hooks and have that impact UI

	hook.Add("RagdollPoser_Gizmo_Transformed", "UI_UpdateTransform", function()
		local selection = RagdollPoser.Selection:GetSelection()
		-- If we've only selected one entity
		if #selection == 2 then
			local bone = selection[1]
			local selectedEntity = selection[2]
			---@cast bone integer
			---@cast selectedEntity ClientEntity
			positionEntry:SetTransform(convertTransformToStr(selectedEntity, bone, RagdollPoser.Gizmo.Mode.Translation))
			rotationEntry:SetTransform(convertTransformToStr(selectedEntity, bone, RagdollPoser.Gizmo.Mode.Rotation))
			scaleEntry:SetTransform(convertTransformToStr(selectedEntity, bone, RagdollPoser.Gizmo.Mode.Scale))
		else
			positionEntry:SetTransform()
			rotationEntry:SetTransform()
			scaleEntry:SetTransform()
		end
	end)

	---@type BoneType|boolean
	local boneTypeRestriction = false
	hook.Add("RagdollPoser_Selection_Selected", "UI_UpdateEntities", function(selection, selectedEntities)
		populateEntities(entitySelector, RagdollPoser.Entity:GetClientEntities(), selectedEntities)
		updateBoneTree(boneTree, selection, boneTypeRestriction)
		local selectedEntity = selection[#selection]
		entitySelector.selected = selectedEntity
		updateConstraintUI(selectedEntity)

		setEnabledConstraintButtons()

		-- If we've only selected one entity
		if #selection == 2 then
			local bone = selection[1]
			positionEntry:SetTransform(convertTransformToStr(selectedEntity, bone, RagdollPoser.Gizmo.Mode.Translation))
			rotationEntry:SetTransform(convertTransformToStr(selectedEntity, bone, RagdollPoser.Gizmo.Mode.Rotation))
			scaleEntry:SetTransform(convertTransformToStr(selectedEntity, bone, RagdollPoser.Gizmo.Mode.Scale))
		else
			positionEntry:SetTransform()
			rotationEntry:SetTransform()
			scaleEntry:SetTransform()
		end
	end)

	hook.Add("RagdollPoser_Constraints_ConstraintCreated", "UI_UpdateEntities", function(entity, constraints)
		local client = RagdollPoser.Entity:GetClientFromEntity(entity)
		if client == entitySelector.selected then
			for _, constraint in ipairs(constraints) do
				makeConstraintEntry(constraintList, entity, constraint)
			end
		end
	end)

	hook.Add("RagdollPoser_Constraints_ConstraintOrderChanged", "UI_UpdateEntities", function(entity)
		local client = RagdollPoser.Entity:GetClientFromEntity(entity)
		-- print("no don't do it!")
		-- if client == entitySelector.selected then
		-- 	updateConstraintUI(client)
		-- end
	end)

	hook.Add("RagdollPoser_UI_Bone_Show", "UI_ShowAllBones", function(boneCategory)
		boneTypeRestriction = self:CategoryToType(boneCategory)
		populateBoneTree(boneTree, RagdollPoser.Selection:GetSelection(), boneTypeRestriction)
	end)
end

---@param cpanel ControlPanel
function MGR:Initialize(cpanel)
	hook.Remove("RagdollPoser_UI_Bone_Show", "UI_ShowAllBones")
	hook.Remove("RagdollPoser_Constraints_ConstraintCreated", "UI_UpdateEntities")
	hook.Remove("RagdollPoser_Selection_Selected", "UI_UpdateEntities")
	hook.Remove("RagdollPoser_Constraints_ConstraintOrderChanged", "UI_UpdateEntities")

	local success, msg = pcall(self.BuildCPanel, self, cpanel)
	if not success and msg then
		ErrorNoHaltWithStack(msg)
	end
end

local firstStart = true
local base = "#tool.ragdollposer.desc"
local phraseCount = 0
local phrase = language.GetPhrase("#tool.ragdollposer.desc1")

function MGR:SelectPhrase(index)
	index = index or math.random(1, phraseCount)
	return language.GetPhrase("#tool.ragdollposer.desc" .. index)
end

function MGR:DrawPhrase(phrase)
	language.Add("tool.ragdollposer.desc", phrase)
end

-- Load all fun subtitles
function MGR:InitializeDraw()
	if firstStart then
		firstStart = false
		for i = 1, 50 do
			local test = language.GetPhrase(base .. i)
			if string.find(test, base) then
				phraseCount = i - 1
				return
			end
		end
	end
end

local math_abs = math.abs
local lastTime = SysTime()
function MGR:Draw()
	local now = SysTime()

	if GetConVar("ragdollposer_funsubtitles"):GetBool() then
		-- Have the phrases change on tool equips
		if math_abs(now - lastTime - RealFrameTime()) > 0.5 then
			phrase = self:SelectPhrase()
		end
		lastTime = now
	else
		phrase = self:SelectPhrase(1)
		lastTime = -(0.5 + SysTime() + RealFrameTime())
	end
	self:DrawPhrase(phrase)
end

MGR:InitializeDraw()

RagdollPoser.UI = MGR

hook.Run("RagdollPoser_UI_Refresh")
