---Handle rendering and collision of gizmo

local RGPFontSize = math.max(math.Round(14 * ScrH() / 1080), 10)

if not RagdollPoser.Fonts then
	RagdollPoser.Fonts = true
	surface.CreateFont("RagdollPoserFont", {
		font = "Verdana",
		size = RGPFontSize,
		weight = 700,
		antialias = true,
	})

	surface.CreateFont("RagdollPoserHeaderFont", {
		font = "Verdana",
		size = RGPFontSize + 4,
		weight = 700,
		antialias = true,
	})
end

local gizmos = {
	---@module "disc"
	disc = include("ragdollposer/client/gizmos/disc.lua"),
	---@module "arrow"
	arrow = include("ragdollposer/client/gizmos/arrow.lua"),
	---@module "scale"
	scale = include("ragdollposer/client/gizmos/scale.lua"),
	---@module "ball"
	ball = include("ragdollposer/client/gizmos/ball.lua"),
	---@module "sidemove"
	sidemove = include("ragdollposer/client/gizmos/sidemove.lua"),
	---@module "sidescale"
	sidescale = include("ragdollposer/client/gizmos/sidescale.lua"),
	---@module "omni"
	omni = include("ragdollposer/client/gizmos/omni.lua"),
}

local MAX_BONE_SIZE = RagdollPoser.Constants.MAX_BONE_SIZE
local OUTLINE_WIDTH = 1
local BLACK = Color(0, 0, 0, 255)
local FLOAT_1DIVIDE540 = 0.00185185185

local isStaticProp = RagdollPoser.Helpers.IsStaticProp

---@class LocalMatrixInfo
---@field [1] integer
---@field [2] VMatrix

---[CLIENT]
---
---Gizmo transform
---
---@class RagdollPoser.Gizmo
local MGR = {
	---@class GizmoProps
	_gizmoProps = {
		pos = Vector(),
		ang = Angle(),
		scale = 30,
		width = 0.25,
		offset = Vector(),
		partial = false,
		sensitivity = 1,
		---@type GizmoOrientation
		orientation = 0,
		localoffset = false,
		relativerotate = false,
		drawsphere = false,
		finalPos = Vector(),
	},

	_moving = false,
	_enabled = true,
	_movingUI = false,

	---@type GizmoBase[]
	_directions = {},
	---@type GizmoMode
	_mode = 0,

	_mirror = false,
	---@type integer
	_gizmoIndex = 0,
	---@type Vector[]
	_intersections = {},

	---All the matrices that we are interested in. We start at the selected bone as our matrix,
	---and then we go down the bone hierarchy and get all matrices to transform.
	---If we also have selected bone matrices as our descendants from the root bone, first transform
	---the root bone, then transform the descendant bones
	---@type table<ClientEntity, table<integer, VMatrix>>
	_matrices = {},
	---@type PoseEvaluationContext
	_poseContext = {
		transformedBones = {},
		transforms = {},
		transformedByClient = {},
		selectedBoneMatrices = {},
		forceCurrentGoal = false,
	},
	---@type table<ClientEntity, table<integer, VMatrix>>
	_constraintMatrices = {},
	---@type table<ClientEntity, VMatrix[]>
	_transformBaseline = {},
	---Matrices local to parent matrices. Useful for transforms
	---@type table<ClientEntity, table<integer, LocalMatrixInfo[]>>
	_localMatrices = {},
	---@type {[Entity]: Vector[]}
	_pivots = {},

	_lastHovering = false,
	_hovering = false,
}

function MGR:UpdateOffset()
	local offset = Vector()
	if MGR._gizmoProps.localoffset then
		offset = self._gizmoProps.offset
	end
	local pos = self._gizmoProps.pos
	local ang = self._gizmoProps.ang
	self._gizmoProps.finalPos = LocalToWorld(offset, angle_zero, pos, ang)
end

function MGR:SetOffset(x, y, z)
	if isvector(x) then
		self._gizmoProps.offset:Set(x)
	else
		self._gizmoProps.offset:SetUnpacked(x, y, z)
	end
	self:UpdateOffset()
	hook.Run("RagdollPoser_Gizmo_OffsetChanged", self._gizmoProps.offset)
end

function MGR:GetOffset()
	return self._gizmoProps.offset
end
---@param selection table
local function setPositionFromSelection(selection)
	local pos = Vector()

	local count = #selection * 0.5
	for i = 1, #selection - 1, 2 do
		local bone = selection[i]
		local entity = selection[i + 1]
		---@cast bone integer
		---@cast entity Entity
		local matrix = entity:GetBoneMatrix(bone)

		if matrix then
			pos:Add(matrix:GetTranslation())
		end
	end
	pos:Div(count)
	MGR:SetPosition(pos)
	MGR:UpdateOffset()
end

---@param selection table
local function setAngleFromSelection(selection)
	local count = #selection
	local bone, entity = selection[count - 1], selection[count]
	if entity then
		local matrix = entity:GetBoneMatrix(bone)
		if matrix then
			MGR:SetAngles(matrix:GetAngles())
		end
	end
end

---How the gizmo is rotated when selecting a bone
---@alias GizmoOrientation integer
MGR.Orientation = {
	World = 0, -- no orientation
	Local = 1, -- oriented to bone
}

---@alias GizmoMode integer
MGR.Mode = {
	Translation = 0,
	Rotation = 1,
	Scale = 2,
}

local numModes = table.Count(MGR.Mode)

---@type {[GizmoMode]: fun(...): GizmoBase}
local modeToInitializer = {
	[MGR.Mode.Translation] = gizmos.arrow,
	[MGR.Mode.Rotation] = gizmos.disc,
	[MGR.Mode.Scale] = gizmos.scale,
}

---@type {[GizmoMode]: fun(...): GizmoBase}
local modeToInitializerSide = {
	[MGR.Mode.Translation] = gizmos.sidemove,
	[MGR.Mode.Scale] = gizmos.sidescale,
}

function MGR:UpdateInitializers()
	modeToInitializer = {
		[MGR.Mode.Translation] = gizmos.arrow,
		[MGR.Mode.Rotation] = gizmos.disc,
		[MGR.Mode.Scale] = gizmos.scale,
	}

	modeToInitializerSide = {
		[MGR.Mode.Translation] = gizmos.sidemove,
		[MGR.Mode.Scale] = gizmos.sidescale,
	}
end

function MGR:SetWidth(width)
	self._gizmoProps.width = width
end

function MGR:SetScale(scale)
	self._gizmoProps.scale = scale
end

function MGR:UpdateOrientation()
	local props = self._gizmoProps
	local orientation = props.orientation
	for _, direction in ipairs(self._directions) do
		direction:UpdateOrientation(orientation, props)
	end
end

---@param mode GizmoMode
function MGR:OnModeChanged(mode)
	self._directions = {}

	for i = 1, 3 do
		local v = Vector()
		v[i] = 1
		local gizmoType = modeToInitializer[mode](v)

		self._directions[i] = gizmoType
	end
	if mode == self.Mode.Rotation then
		-- Big disc

		local disc, ball = gizmos.disc(), gizmos.ball()
		self._directions[4] = disc
		self._directions[5] = ball
	elseif mode == self.Mode.Scale or mode == self.Mode.Translation then
		for i = 4, 6 do
			local v = Vector()
			v[i - 3] = 1
			local gizmoType = modeToInitializerSide[mode](v)
			self._directions[i] = gizmoType
		end
		if mode == self.Mode.Translation then
			self._directions[7] = gizmos.omni()
		end
	end
	self:UpdateOrientation()
end

function MGR:CycleMode()
	self._mode = (self._mode + 1) % numModes
	return self._mode
end

---@param pos Vector
function MGR:SetPosition(pos)
	self._gizmoProps.pos = pos
end

---@param ang Angle
function MGR:SetAngles(ang)
	self._gizmoProps.ang = ang
	self:UpdateOrientation()
end

---@return Vector
function MGR:GetPosition()
	return self._gizmoProps.pos
end

---@return Angle
function MGR:GetAngles()
	return self._gizmoProps.ang
end

---@param state boolean
function MGR:SetMoving(state)
	self._moving = state
end

---@param state boolean
function MGR:SetMovingUI(state)
	self._movingUI = state
end

function MGR:GetMoving()
	return self._moving
end

function MGR:IsMoving()
	return self._moving
end

function MGR:IsEnabled()
	return self._enabled
end

function MGR:SetEnabled(enabled)
	self._enabled = enabled
end

RagdollPoser.Networking.SendSubPose = RagdollPoser.Networking.DefineSender("SendSubPose")

local entityBuffer = {}

local function sendSubPoseResponse()
	for _, entity in ipairs(entityBuffer) do
		RagdollPoser.Entity.UpdateRenderBounds(entity)
	end
	entityBuffer = {}

	-- TODO: Update the client entity if we don't have stretching enabled

	local selection = RagdollPoser.Selection:GetSelection()
	MGR:SetTransformFromSelection(selection)
	MGR:SetTransformFromSelection(selection)
	hook.Run("RagdollPoser_Gizmo_Transformed")
end
RagdollPoser.Networking.DefineReceiver("SendSubPoseResponse", sendSubPoseResponse)

local function setOffset()
	local worldPos = net.ReadVector()
	local offset = WorldToLocal(worldPos, angle_zero, MGR._gizmoProps.pos, MGR._gizmoProps.ang)
	MGR:SetOffset(offset.x, offset.y, offset.z)
end
RagdollPoser.Networking.DefineReceiver("SetOffset", setOffset)

function MGR:TestIntersect()
	-- Gizmos don't have a sense of depth, so we need to measure the depth after collecting depth interests
	local eyepos, eyevec, eyeang = RagdollPoser.View:GetView()
	local directions = self._directions
	local intersections = self._intersections
	for i, direction in ipairs(directions) do
		intersections[i] = direction:Intersect(eyepos, eyevec, self._gizmoProps)
	end

	local targetIndex, closestDistance = 0, math.huge
	-- first, only go through the first 3. prioritize these guys over the special gizmos
	for i = 1, 3 do
		local hitpos = intersections[i]
		if hitpos then
			local distance = hitpos:LengthSqr()
			if distance < closestDistance then
				closestDistance = distance
				targetIndex = i
			end
		end
	end

	-- Prioritize the omnipos gizmo over everything else
	if intersections[7] then
		targetIndex = 7
	end

	if targetIndex <= 0 then
		-- Go through the special ones if we didn't get an intersection earlier
		for i = 4, #directions do
			local hitpos = intersections[i]
			if hitpos then
				local distance = hitpos:LengthSqr()
				if distance < closestDistance then
					closestDistance = distance
					targetIndex = i
				end
			end
		end
	end

	self._hovering = RagdollPoser.Selection:GetSelection()[1] and targetIndex > 0
	if self._hovering ~= self._lastHovering then
		hook.Run("RagdollPoser_Gizmo_Hovering", self._hovering)
	end
	self._lastHovering = self._hovering
	if targetIndex > 0 then
		self._gizmoIndex = targetIndex
		return true
	end

	return false
end

local IDENTITY_MATRIX = Matrix()
IDENTITY_MATRIX:Identity()

---@return GizmoOrientation
function MGR:GetOrientation()
	return self._gizmoProps.orientation
end

---@param newOrientation GizmoOrientation
function MGR:SetOrientation(newOrientation)
	self._gizmoProps.orientation = newOrientation
end

---@return GizmoMode
function MGR:GetMode()
	return self._mode
end

---Do some setup (caching) before we start transforming
function MGR:PreTransform()
	self._transformOk = false

	-- Get an initial copy of the entity matrices

	local selection = RagdollPoser.Selection:GetSelection()
	if not selection[1] then
		return
	end

	---Go through a client and copy its matrices for local matrices (wrt to parent bone) and its parent bone relationships
	---@param client ClientEntity
	---@param boneMatrices VMatrix[]
	---@param bone integer
	---@param storeLocal {[integer]: VMatrix}
	---@param parents {[integer]: integer}
	local function recursiveMatrixCopy(client, boneMatrices, bone, storeLocal, parents)
		local m = boneMatrices[bone + 1]
		if not self._transformedBoneSet[client][bone] then
			self._transformedBoneSet[client][bone] = table.insert(self._transformedBones[client], bone)
		end
		for _, childBone in ipairs(client:GetChildBones(bone)) do
			local childMatrix = boneMatrices[childBone + 1]
			if childMatrix and m then
				table.insert(storeLocal, { childBone, m:GetInverse() * childMatrix })
				parents[childBone] = bone
			end
			recursiveMatrixCopy(client, boneMatrices, childBone, storeLocal, parents)
		end
	end

	--- If relative rotate is enabled. If it is, rotate with respect to the current offsetted gizmo. Otherwise, rotate with respect to each bones own pivot
	--- Also need to update local matrices. Say we rotate a parent bone and we have also selected a child bone: we wnat to rotate that one after the parent bone has been rotated. so that the child bone is in the right spot

	-- TODO: Maybe simplify the tables used below for doing transforms?
	-- There could be a simpler, possibly more performant way to doing things
	self._matrices = {}
	self._constraintMatrices = {}
	self._transformBaseline = {}
	self._localMatrices = {}
	-- Including the selected bone and its descendants, these are the bones that have been moved (includes bones affected by IK chains and bones locked to each other)
	-- Array set: Don't want to work with the same bones
	self._transformedBones = {}
	self._transformedBoneSet = {}
	self._transformed = {}
	self._initials = {}
	self._parents = {}
	self._accumulations = {}
	-- TODO: Track pivots for each bone, if I wanted to add the ability to rotate all bones by their individual axis
	self._pivots = {}

	local function addTransformedBones(client, bones)
		if not bones then
			return
		end

		self._transformedBones[client] = self._transformedBones[client] or {}
		self._transformedBoneSet[client] = self._transformedBoneSet[client] or {}
		for _, bone in ipairs(bones) do
			if not self._transformedBoneSet[client][bone] then
				self._transformedBoneSet[client][bone] = true
				table.insert(self._transformedBones[client], bone)
			end
		end
	end

	local function collectBones(selection)
		-- Collection of bones per entity, starting from the selected root bone index to the selected descendant bone index
		local entityBones = {}
		---@type {[Entity]: {[integer]: integer}}
		local entityBoneSet = {}

		-- First, we need to select all bones and do our iteration with the root first, and then the descendants, for each entity
		-- After we do that, then we can copy our matrices over. Then what will happen is that we process the root matrices first,
		-- and then the descendant matrices
		-- Problem, bone selections are not ordered. We need to figure out the order using the client bone hierarchy
		for i = 1, #selection - 1, 2 do
			local bone, client = selection[i], selection[i + 1]
			---@cast bone integer
			---@cast client ClientEntity
			entityBones[client] = entityBones[client] or {}
			entityBoneSet[client] = entityBoneSet[client] or {}
			entityBoneSet[client][bone] = 0
		end

		-- What are we doing here? We're sorting selected bones based on their depth from the root bone
		-- We work with the bones with less depth first (parent bones) and then bones with more depth last (child bones)
		for i = 1, #selection - 1, 2 do
			local bone, client = selection[i], selection[i + 1]
			local tree = RagdollPoser.Entity.GetDefaultPoseTreeFor(client)

			local count = 0
			local walk = bone
			while tree[walk + 1] do
				if entityBoneSet[client][walk] then
					count = count + 1
				end
				walk = tree[walk + 1][5]
			end
			entityBoneSet[client][bone] = count
		end

		-- After getting our entity matrices, we need to calculate the directions which we do the transform
		local gizmo = self._directions[self._gizmoIndex]
		local props = self._gizmoProps

		-- sort entity bone set per client by number of bones
		for client, bones in pairs(entityBoneSet) do
			for bone, count in SortedPairsByValue(bones) do
				table.insert(entityBones[client], bone)
			end

			self._pivots[client] = self._pivots[client] or { gizmo:GetDirection(props) }
		end

		-- iterate over every selected bone in order from root bone to descendant bone
		-- and get their matrices
		for client, bones in pairs(entityBones) do
			local matrices = RagdollPoser.Entity.GetMatricesFromClient(client)
			if matrices then
				self._transformBaseline[client] = {}
				for bone = 0, client:GetBoneCount() - 1 do
					local matrix = matrices[bone + 1]
					if matrix then
						self._transformBaseline[client][bone + 1] = matrix * IDENTITY_MATRIX
					end
				end

				self._matrices[client] = self._matrices[client] or {}
				self._constraintMatrices[client] = self._constraintMatrices[client] or {}
				self._localMatrices[client] = self._localMatrices[client] or {}
				self._parents[client] = self._parents[client] or {}
				self._initials[client] = self._initials[client] or {}
				self._transformedBoneSet[client] = self._transformedBoneSet[client] or {}
				self._transformedBones[client] = self._transformedBones[client] or {}
				self._transformed[client] = self._transformed[client] or {}
				for i, bone in ipairs(bones) do
					local boneMatrix = client:GetBoneMatrix(bone)
					self._matrices[client][bone] = boneMatrix
					self._constraintMatrices[client][bone] = {}
					self._localMatrices[client][bone] = self._localMatrices[client][bone] or {}
					self._initials[client][bone] = self._initials[client][bone] or {}
					recursiveMatrixCopy(
						client,
						matrices,
						bone,
						self._localMatrices[client][bone],
						self._parents[client]
					)
					self._constraintMatrices[client][bone] = boneMatrix * IDENTITY_MATRIX
				end
			end
		end

		-- For mirroring compatibility:
		-- 1. Store pivot per client
		-- 2. Iterate over each clients' pivots using root bone data structure
		-- 3. With root bone known, flip direction of pivots using mirror axis

		for client, pivots in pairs(self._pivots) do
			self._accumulations[client] = self._accumulations[client] or {}
			for i, pivot in ipairs(pivots) do
				pivots[i] = gizmo:PreTransform(pivot, self._initials)
				self._accumulations[client][i] = 0
			end
		end
	end

	collectBones(selection)

	self._mirroredSelection = {}
	-- Also operate with entity matrices for the mirrored bones, using the same settings for the above, except
	-- these must be relative to where the entity is facing
	-- The desired mirror plane might not be the same for all models, so we'll give the option to change the mirror plane so we get proper
	-- mirroring for every model
	if self._mirror then
		local mirroredSelection = RagdollPoser.Mirror:GetMirrored(selection)
		self._mirrorAxis = GetConVar("ragdollposer_mirror_axis"):GetInt()
		collectBones(mirroredSelection)

		-- We use the root bone as our mirror plane
		-- This assumes that the mirrored bone is truly symmetric to the bone with respect to the root mirror plane
		---@type {[Entity]: VMatrix}
		local rootBones = {}
		local maxBones = 256
		for i = 1, #mirroredSelection - 1, 2 do
			local bone, entity = mirroredSelection[i], mirroredSelection[i + 1]
			---@cast bone integer
			---@cast entity Entity

			RagdollPoser.Entity.ExposeBones(entity)

			rootBones[entity] = rootBones[entity] or Matrix()
			if self._parents[entity] then
				local iter = 0
				local walk = bone
				while walk ~= -1 and iter < maxBones do
					local parent = entity:GetBoneParent(walk)
					if parent == -1 then
						entity:CopyBoneMatrix(walk, rootBones[entity])
						rootBones[entity]:SetTranslation(vector_origin)
					end
					walk = parent
					iter = iter + 1
				end
			end
		end

		self._mirrorPivots = {}
		for entity, rootMatrix in pairs(rootBones) do
			local pivot = self._pivots[entity]
			self._mirrorPivots[entity] = self._mirrorPivots[entity] or {}
			for i, p in ipairs(pivot) do
				local localDirection = rootMatrix:GetInverse() * p
				localDirection[self._mirrorAxis + 1] = -localDirection[self._mirrorAxis + 1]
				self._mirrorPivots[entity][i] = rootMatrix * localDirection
			end
		end
		self._mirroredSelection = mirroredSelection
	end

	local x, y = input.GetCursorPos()
	local newPos = RagdollPoser.View:GetView()
	self.start = gui.ScreenToVector(x, y)
	self.startPos = newPos

	-- After getting transformed bones for the selected bones, we have to consider constrained bones
	-- Even if they're not within our initial transformed bone set, we'll have to add them anyway

	local evaluatedEntities = {}
	-- added by gpt for IK and lock constraints
	local function preEvaluateConstraints(selectionToEvaluate)
		for i = 1, #selectionToEvaluate - 1, 2 do
			local _, client = selectionToEvaluate[i], selectionToEvaluate[i + 1]
			---@cast client ClientEntity
			local entity = RagdollPoser.Entity.GetEntityFromClient(client)
			if not evaluatedEntities[entity] then
				local bonesByEntity = RagdollPoser.Constraints:PreEvaluate(entity)
				evaluatedEntities[entity] = true
				for affectedEntity, bones in pairs(bonesByEntity) do
					local affectedClient = RagdollPoser.Entity.GetClientFromEntity(affectedEntity)
					if IsValid(affectedClient) then
						addTransformedBones(affectedClient, bones)
					end
				end
			end
		end
	end
	preEvaluateConstraints(selection)
	preEvaluateConstraints(self._mirroredSelection)

	self._transformOk = true
end

---Transform the selected bones of the selected entities, after triggering a move operation
function MGR:Transform()
	if not self._transformOk then
		return
	end

	local x, y = input.GetCursorPos()
	local newPos = RagdollPoser.View:GetView()
	local newPoint = gui.ScreenToVector(x, y)
	local eyeDelta = newPos - self.startPos
	self.delta = newPoint - self.start

	local gizmo = self._directions[self._gizmoIndex]
	if gizmo then
		-- TODO: Replace selection with the entities we want to manipulate, which includes selected entities/bones and any entities constrained
		-- to our selected
		local selection = RagdollPoser.Selection:GetSelection()
		for client, baseline in pairs(self._transformBaseline) do
			local matrices = RagdollPoser.Entity.GetMatricesFromClient(client)
			if matrices then
				for index, matrix in pairs(baseline) do
					if matrices[index] then
						matrices[index]:Set(matrix)
					end
				end
			end
		end

		local function transformSelected(selection, pivots, doMirror)
			for i = 1, #selection - 1, 2 do
				local bone, client = selection[i], selection[i + 1]
				---@cast client ClientEntity
				local entity = RagdollPoser.Entity.GetEntityFromClient(client)
				RagdollPoser.Entity.ExposeBones(client)
				RagdollPoser.Entity.ExposeBones(entity)
				-- TODO: Pass the gizmo object? This will greatly simplify the function header, possibly at cost of larger function body

				-- We'll build the transform step by step
				-- 1. Process delta
				-- 2. Perform transform with delta
				-- 3. Post transform
				-- 4. Mirroring
				-- 5. Constraints

				local deltaProps
				if self._movingUI then
					deltaProps = gizmo:ProcessDeltaUI(
						self.start,
						newPoint,
						self._gizmoProps,
						doMirror and self._mirrorAxis or -1,
						RagdollPoser.UI:GetDelta()
					)
				else
					deltaProps = gizmo:ProcessDelta(
						self.start,
						newPoint,
						self._gizmoProps,
						doMirror and self._mirrorAxis or -1,
						eyeDelta
					)
				end

				-- Move the selected bone
				self._transformed[client][bone] = gizmo:Transform(
					pivots[client],
					deltaProps,
					self._matrices[client][bone],
					self._accumulations[client],
					self._initials[client][bone],
					self._gizmoProps
				)

				-- Resolve parent bone hierarchies (if I moved an arm, all the child bones of that should move along with it)
				gizmo:PostTransform(
					self._transformed[client][bone],
					self._localMatrices[client][bone],
					self._parents[client],
					self._transformed[client]
				)

				local constrainedMatrix = self._constraintMatrices[client][bone]
				constrainedMatrix:Set(self._matrices[client][bone])

				RagdollPoser.Constraints:Evaluate(
					entity,
					bone,
					constrainedMatrix,
					self._localMatrices[client][bone],
					self._parents[client],
					self._transformed[client]
				)
				RagdollPoser.Constraints:PostEvaluate(
					entity,
					bone,
					self._localMatrices[client][bone],
					self._parents[client],
					self._transformed[client]
				)

				local matrices = RagdollPoser.Entity.GetMatricesFromClient(client)

				if matrices then
					for _, b in ipairs(self._transformedBones[client]) do
						local targetMatrix = matrices[b + 1]
						if targetMatrix and self._transformed[client][b] then
							targetMatrix:Set(self._transformed[client][b])
						end
					end
				end
			end
		end

		transformSelected(selection, self._pivots, false)
		if self._mirroredSelection[1] then
			transformSelected(self._mirroredSelection, self._mirrorPivots, true)
		end

		for client, transformedBones in pairs(self._transformedBones) do
			local entity = RagdollPoser.Entity.GetEntityFromClient(client)
			if not IsValid(entity) or not self._transformed[client] then
				continue
			end

			local outputClient = RagdollPoser.Entity.GetClientFromEntity(entity)
			if not IsValid(outputClient) then
				continue
			end
			RagdollPoser.Entity.ExposeBones(outputClient)
			RagdollPoser.Entity.ExposeBones(entity)
			local matrices = RagdollPoser.Entity.GetMatricesFromClient(outputClient)
			if matrices then
				local poseContext = self._poseContext
				poseContext.transformedBones = transformedBones
				poseContext.transforms = matrices
				poseContext.transformedByClient = self._transformed
				poseContext.selectedBoneMatrices = self._matrices[client]
				poseContext.forceCurrentGoal = false
				RagdollPoser.Constraints:EvaluatePose(entity, poseContext)
			end
		end
	end

	-- After caching our directions,
	-- Do transform to initial copy, and apply new transform to
	-- entity matrices so that we see the effect on the ghost client entity
	self.start = newPoint
	self.startPos = newPos
end

local function doTransform()
	-- FIXME: Make this not run while we are holstering
	-- We can also just disable the input system when we are holstering, to prevent the left-click event altogether
	local equipped = RagdollPoser.Helpers.Equipped()
	if equipped and RagdollPoser.Selection:GetSelection()[1] and MGR:IsEnabled() and MGR:IsMoving() then
		MGR:Transform()
	end
end

-- HACK: using 2 hooks to get mouse input from locked and unlocked cursor states
hook.Remove("Think", "RagdollPoser_Gizmo_Transform")
hook.Add("Think", "RagdollPoser_Gizmo_Transform", doTransform)
hook.Remove("InputMouseApply", "RagdollPoser_Gizmo_Transform")
hook.Add("InputMouseApply", "RagdollPoser_Gizmo_Transform", doTransform)

---Bone matrices and entity's angles aren't consistent with each other
---so we need to correct this
---@param entity Entity
---@param bone integer
---@param matrix VMatrix
local function fixAngleOffset(entity, bone, matrix)
	local m1 = Matrix()
	m1:Rotate(entity:GetAngles())
	local m2 = Matrix()
	m2:Rotate(entity:GetBoneMatrix(bone):GetAngles())
	local offset = m2:GetTransposed() * m1
	local trace = offset:GetField(1, 1) + offset:GetField(2, 2) + offset:GetField(3, 3)
	local difference = math.acos(math.Clamp((trace - 1) * 0.5, -1, 1))
	if difference >= 1e-6 then
		local rotation = matrix * offset
		matrix:SetAngles(rotation:GetAngles())
	end
end

---Send update bone transforms of the selected bone hierarchy
---@param selection Selection
local function sendSubPose(selection)
	-- TODO: Do a server acknowledge step so that the server only accepts poses that we send from here, not from
	-- anywhere else

	-- Selection structure
	-- Entity A
	-- Bones
	-- Matrix
	-- Entity B
	-- ...

	entityBuffer = {}
	---@type Entity[]
	local entities = entityBuffer
	---@type {[Entity]: integer[]}
	local bones = {}
	---@type {[Entity]: {[integer]: true}}
	local boneSet = {}

	---@param entity Entity
	---@param bone integer
	local function addChildBones(entity, bone, arr, set)
		table.insert(arr, bone)
		set[bone] = true
		for _, childBone in ipairs(entity:GetChildBones(bone)) do
			if not set[childBone] then
				addChildBones(entity, childBone, arr, set)
			end
		end
	end

	for i = 1, #selection - 1, 2 do
		local bone = selection[i] --[[@as integer]]
		local client = selection[i + 1] --[[@as ClientEntity]]
		local entity = RagdollPoser.Entity.GetEntityFromClient(client)
		RagdollPoser.Entity.ExposeBones(client)
		RagdollPoser.Entity.ExposeBones(entity)

		local arr = bones[entity]
		local set = boneSet[entity]
		if not bones[entity] then
			arr = {}
			set = {}
			bones[entity] = arr
			boneSet[entity] = set
			table.insert(entities, entity)
		end

		if not set[bone] then
			addChildBones(entity, bone, arr, set)
		end
	end

	-- pyraMid of geez! uhh
	-- FIXME: why did A.I. make this?
	-- Oh, so that it will track entities from lock bones or bonemerge or IKs. bro
	local entityIndex = 1
	while entityIndex <= #entities do
		local entity = entities[entityIndex]
		for _, constraint in ipairs(RagdollPoser.Constraints:GetConstraintStack(entity)) do
			local outputEntity = constraint.GetOutputEntity and constraint:GetOutputEntity() or entity
			local root = constraint.GetOutputRoot and constraint:GetOutputRoot()
			if IsValid(outputEntity) and root then
				RagdollPoser.Entity.ExposeBones(outputEntity)
				local arr = bones[outputEntity]
				local set = boneSet[outputEntity]
				if not arr then
					arr = {}
					set = {}
					bones[outputEntity] = arr
					boneSet[outputEntity] = set
					table.insert(entities, outputEntity)
				end
				if not set[root] then
					addChildBones(outputEntity, root, arr, set)
				end
			end
		end
		entityIndex = entityIndex + 1
	end

	-- Shared matrix for copying into, to prevent garbage collection
	local boneMatrix = Matrix()

	RagdollPoser.Networking.SendSubPose()
	net.WriteUInt(#entities, 13)
	for _, entity in ipairs(entities) do
		local isBonemerge = RagdollPoser.Bonemerge:IsBonemergeEntity(entity)

		local client = RagdollPoser.Entity.GetClientFromEntity(entity)
		RagdollPoser.Entity.ExposeBones(entity)
		RagdollPoser.Entity.ExposeBones(client)
		net.WriteEntity(entity)
		local matrices = RagdollPoser.Entity.GetMatrices(entity)
		local bs = bones[entity]
		local count = #bs
		net.WriteUInt(count, 8)
		local physCount = RagdollPoser.Entity.GetPhysBoneCount(entity)
		for _, b in ipairs(bs) do
			net.WriteUInt(b, 8)
			local matrix = matrices[b + 1] * IDENTITY_MATRIX

			local physbone = RagdollPoser.Helpers.BoneToPhysBone(entity, b)
			if not isBonemerge and (physbone >= 0 or isStaticProp(entity)) then
				-- Compare if bone matrices and angles match up
				-- if not, then we need to apply corrections
				-- TODO: Does this happen with ragdolls too?
				-- TODO: Add parented entity layer so that matrices sent there is correct
				-- All bonemerged entities use manipulates, while parented use setpos/setang
				if physCount == 1 then
					fixAngleOffset(entity, b, matrix)
				end

				-- Send world transforms and everything
				net.WriteMatrix(matrix)
			else
				if isBonemerge then
					RagdollPoser.Bonemerge:GetBonemergePose(entity, b, boneMatrix)
					-- boneMatrix:SetScale(matrix:GetScale())
				else
					RagdollPoser.Helpers.GetNonPhysicalBonePose(client, b, boneMatrix)
					boneMatrix:SetScale(matrix:GetScale())
				end
				net.WriteMatrix(boneMatrix)
			end
		end
	end
	net.SendToServer()
end

---@param transformType GizmoMode
function MGR:ResetSelected(transformType, bone, entity)
	local selection = RagdollPoser.Selection:GetSelection()
	if not selection[1] then
		return
	end
	local resetAll = transformType == 4

	local function handleReset(bone, client)
		local defaultPose = RagdollPoser.Entity.GetDefaultPoseTreeFor(client)
		local matrices = RagdollPoser.Entity.GetMatricesFromClient(client)
		local entity = RagdollPoser.Entity.GetEntityFromClient(client)
		local selectedMatrix = matrices and matrices[bone + 1]
		local pose = defaultPose[bone + 1]
		if not selectedMatrix or not pose then
			return
		end

		if resetAll or transformType == self.Mode.Scale then
			-- TODO: Also reset translation and rotation back to local offsets
			local function resetDescendantScales(parentBone)
				local parentMatrix = matrices[parentBone + 1]
				if not parentMatrix then
					return
				end

				for _, childBone in ipairs(client:GetChildBones(parentBone)) do
					local childMatrix = matrices[childBone + 1]
					if childMatrix then
						childMatrix:SetScale(Vector(1, 1, 1))
						resetDescendantScales(childBone)
					end
				end
			end

			selectedMatrix:SetScale(Vector(1, 1, 1))
			resetDescendantScales(bone)
		end

		if resetAll or transformType == self.Mode.Translation or transformType == self.Mode.Rotation then
			-- Save each descendant's transform relative to its immediate parent so the
			-- selected bone can be reset without changing the pose below it.
			local descendantLocals = {}
			local function saveDescendants(parentBone)
				local parentMatrix = matrices[parentBone + 1]
				if not parentMatrix then
					return
				end

				for _, childBone in ipairs(client:GetChildBones(parentBone)) do
					local childMatrix = matrices[childBone + 1]
					if childMatrix then
						local inverseParent = parentMatrix:GetInverse() or parentMatrix:GetInverseTR()
						descendantLocals[childBone] = inverseParent * childMatrix
						saveDescendants(childBone)
					end
				end
			end

			saveDescendants(bone)

			local parentBone = client:GetBoneParent(bone)
			local parentMatrix
			if parentBone >= 0 then
				parentMatrix = matrices[parentBone + 1]
			else
				parentMatrix = Matrix()
				parentMatrix:SetTranslation(entity:GetPos())
				parentMatrix:SetAngles(entity:GetAngles())
			end

			if parentMatrix then
				local resetPos, resetAng = LocalToWorld(
					parentBone >= 0 and pose[3] or pose[1],
					parentBone >= 0 and pose[4] or pose[2],
					parentMatrix:GetTranslation(),
					parentMatrix:GetAngles()
				)

				if resetAll or transformType == self.Mode.Translation then
					selectedMatrix:SetTranslation(resetPos)
				end
				if resetAll or transformType == self.Mode.Rotation then
					local scale = selectedMatrix:GetScale()
					if parentBone >= 0 then
						selectedMatrix:SetAngles(resetAng)
					end
					selectedMatrix:SetScale(scale)
				end

				local function restoreDescendants(parentBoneToRestore)
					local parent = matrices[parentBoneToRestore + 1]
					if not parent then
						return
					end

					for _, childBone in ipairs(client:GetChildBones(parentBoneToRestore)) do
						local childMatrix = matrices[childBone + 1]
						local localMatrix = descendantLocals[childBone]
						if childMatrix and localMatrix then
							childMatrix:Set(parent * localMatrix)
							restoreDescendants(childBone)
						end
					end
				end

				restoreDescendants(bone)
			end
		end
	end

	if bone and entity then
		handleReset(bone, entity)
	else
		for i = 1, #selection - 1, 2 do
			local bone = selection[i]
			local client = selection[i + 1]
			---@cast bone integer
			---@cast client ClientEntity
			handleReset(bone, client)
		end
	end

	local complete = table.Copy(selection)
	sendSubPose(complete)
end

---Send our results after the transformation
function MGR:PostTransform()
	local gizmo = self._directions[self._gizmoIndex]
	if gizmo then
		gizmo:FinishTransform()
	end

	local selection = RagdollPoser.Selection:GetSelection()
	local mirrorSelection = self._mirroredSelection or {}
	local complete = table.Copy(selection)
	if selection[1] then
		if mirrorSelection[1] then
			for i = 1, #mirrorSelection do
				complete[#complete + 1] = mirrorSelection[i]
			end
		end
		sendSubPose(complete)
	end
end

local function onLeftClickDown(x, y, tr)
	RagdollPoser.Input:ResetDelta()
	-- If we're not accepting drag selections, then don't do anything
	if RagdollPoser.Selection:GetSelection()[1] and MGR:IsEnabled() and not MGR:IsMoving() and MGR:TestIntersect() then
		-- Click on gizmo and do stuff
		MGR:SetMoving(true)
		MGR:PreTransform()
	end
end
local function onLeftClickUp(x, y, tr)
	if MGR:IsMoving() then
		-- After doing stuff, apply final transforms, send to server
		local success, err = pcall(MGR.PostTransform, MGR)
		if not success then
			ErrorNoHaltWithStack("There was an error when attempting to complete the transform:\n", err, "\n")
		end
		MGR:SetMoving(false)
	end
end
hook.Add("RagdollPoser_Input_LeftClickDown", "Gizmo", onLeftClickDown)
hook.Add("RagdollPoser_Input_LeftClickUp", "Gizmo", onLeftClickUp)

-- Instead of creating a matrix with `GetMatrix`, copy the values
-- to this one, to reduce garbace collection cycles
local mat = Matrix()

-- TODO: Use new theme module for providing colors
local GREEN = Color(0, 255, 0, 255)
local CYAN = Color(0, 128, 255, 255)
local RED = Color(255, 0, 0, 255)
local YELLOW = Color(255, 255, 0, 255)

-- TODO: Use themings
local boneTypeToColor = {
	[RagdollPoser.Bones.BoneType.Physics] = GREEN,
	[RagdollPoser.Bones.BoneType.Manipulate] = CYAN,
	[RagdollPoser.Bones.BoneType.Procedural] = RED,
}

---@param theme Theme
local function updateTheme(theme)
	boneTypeToColor[RagdollPoser.Bones.BoneType.Physics] = theme.gizmoColors.physics
	boneTypeToColor[RagdollPoser.Bones.BoneType.Manipulate] = theme.gizmoColors.manipulate
	boneTypeToColor[RagdollPoser.Bones.BoneType.Procedural] = theme.gizmoColors.procedural
end
hook.Add("RagdollPoser_Themes_Update", "Gizmo", updateTheme)

-- Make sure you are in the 2D rendering context
function MGR:DrawBones()
	local mouseHovered = {}
	local bones = RagdollPoser.Bones
	local boneTypes = bones.BoneType
	local selection = RagdollPoser.Selection
	if selection:GetEnabled() then
		local ents = RagdollPoser.Entity.GetClientEntities()
		for _, ent in ipairs(ents) do
			if not IsValid(ent) then
				continue
			end

			RagdollPoser.Entity.ExposeBones(ent)

			table.insert(mouseHovered, ent)
			for b = 0, ent:GetBoneCount() - 1 do
				local name = ent:GetBoneName(b)
				if name == "__INVALIDBONE__" then
					continue
				end

				ent:CopyBoneMatrix(b, mat)
				local p = mat:GetTranslation()
				local data = p:ToScreen()
				if not data.visible then
					continue
				end
				local tx, ty = data.x, data.y
				local x, y = input.GetCursorPos()
				local boneType = bones:GetBoneType(ent, b)
				if selection._filter and selection._filter ~= boneType then
					continue
				end
				local color = boneTypeToColor[boneType]

				local pointSelected = selection:RaycastBone(x, y, tx, ty)
				if pointSelected then
					color = YELLOW
					table.insert(mouseHovered, b)
				end

				surface.DrawCircle(tx, ty, MAX_BONE_SIZE, color)

				local childSelected = false
				for _, childBone in ipairs(ent:GetChildBones(b)) do
					ent:CopyBoneMatrix(childBone, mat)
					local p = mat:GetTranslation()
					local data = p:ToScreen()
					if not data.visible then
						continue
					end

					local cx, cy = data.x, data.y

					if not pointSelected and not childSelected and selection:RaycastBoneLine(x, y, tx, ty, cx, cy) then
						color = YELLOW
						table.insert(mouseHovered, b)
						childSelected = true
					end

					surface.SetDrawColor(color.r, color.g, color.b, color.a)
					surface.DrawLine(tx, ty, cx, cy)
				end
			end
		end
	end

	return mouseHovered
end

-- Make sure you are in the 3D rendering context
function MGR:Draw()
	RagdollPoser.Constraints:Draw()
	if not self:IsEnabled() then
		return
	end

	local props = self._gizmoProps

	if props.pos then
		-- render.SetColorMaterialIgnoreZ()
		-- render.CullMode(MATERIAL_CULLMODE_NONE)
		-- render.DrawBox(props.pos, props.ang, tempMin, tempMax)
		if self:IsMoving() then
			local direction = self._directions[self._gizmoIndex]
			direction:Draw(props, true)
		else
			local selected = self:TestIntersect()
			for i, direction in ipairs(self._directions) do
				direction:Draw(props, selected and i == self._gizmoIndex)
			end
		end
	end
end

local hovered = {}
-- This hook runs repeatedly!
hook.Add("RagdollPoser_Selection_Hover", "Gizmo", function(bone, entity)
	hovered = {}
	if bone and IsValid(entity) then
		hovered[entity] = bone
	end
end)

local BLUE = Color(0, 0, 255, 255)
local hoverMat = Matrix()
function MGR:DrawHovered()
	for entity, bone in pairs(hovered) do
		entity:CopyBoneMatrix(bone, hoverMat)
		local p = hoverMat:GetTranslation()
		local data = p:ToScreen()
		if not data.visible then
			continue
		end
		local tx, ty = data.x, data.y
		local color = BLUE

		-- TODO: Categorize based on bone type
		surface.DrawCircle(tx, ty, MAX_BONE_SIZE, color)
		for _, childBone in ipairs(entity:GetChildBones(bone)) do
			entity:CopyBoneMatrix(childBone, mat)
			local p = mat:GetTranslation()
			local data = p:ToScreen()
			if not data.visible then
				continue
			end

			local cx, cy = data.x, data.y

			surface.DrawLine(tx, ty, cx, cy)
		end
		local boneName = entity:GetBoneName(bone)
		draw.SimpleTextOutlined(
			boneName,
			"RagdollPoserFont",
			tx,
			ty,
			color,
			TEXT_ALIGN_LEFT,
			TEXT_ALIGN_BOTTOM,
			OUTLINE_WIDTH,
			BLACK
		)
	end
	hovered = {}
end

-- TODO: Move drawing functions into another file? render.lua
function MGR:DrawSelected()
	local selection = RagdollPoser.Selection:GetSelection()
	for i = 1, #selection - 1, 2 do
		local bone, entity = selection[i], selection[i + 1]
		---@cast bone integer
		---@cast entity Entity

		if not IsValid(entity) then
			continue
		end
		RagdollPoser.Entity.ExposeBones(entity)
		local matrix = entity:GetBoneMatrix(bone)
		local data = matrix:GetTranslation():ToScreen()
		if not data.visible then
			continue
		end
		surface.DrawCircle(data.x, data.y, MAX_BONE_SIZE, YELLOW)
	end
end

---@param mouseHovered Entity[]|integer[]
function MGR:DrawBoneNames(mouseHovered)
	local targetEntity = NULL
	local mx, my = input.GetCursorPos()

	local maxItemsPerColumn = 257 * (RGPFontSize + 3)
	local scrH = ScrH() - 100 -- Some padding to keep the bones centered
	local columns = 0

	local midw, midh = ScrW() / 2, ScrH() / 2
	local meanNameLength = 0
	-- Assume default font is about this wide
	local fontWidth = 7.5 * FLOAT_1DIVIDE540 * midh
	if fontWidth < 6.5 then
		fontWidth = 6.5
	end
	for i = 1, #mouseHovered do
		local entry = mouseHovered[i]
		if isentity(entry) then
			---@cast entry Entity
			targetEntity = entry
		elseif IsValid(targetEntity) then
			---@cast entry integer
			meanNameLength = meanNameLength + #targetEntity:GetBoneName(entry) * fontWidth
		end
	end

	local j = 0
	for i = 1, #mouseHovered do
		local entry = mouseHovered[i]
		local nextEntry = mouseHovered[i + 1]
		local shouldIncrement = isnumber(entry) or isnumber(nextEntry)

		if shouldIncrement then
			j = j + 1
		end

		-- List the selected bones. If they attempt to overflow through the screen, add the items to another column.
		local yPos = my + (j % maxItemsPerColumn) * (RGPFontSize + 3)
		local xPos = mx + 5 + meanNameLength * columns
		if yPos > scrH then
			maxItemsPerColumn = j + 1
		end
		if j > 1 and j % maxItemsPerColumn == 0 then
			columns = columns + 1
			xPos = mx + 5 + meanNameLength * columns
		end

		if isentity(entry) then
			---@cast entry Entity
			targetEntity = entry
			if isnumber(nextEntry) then
				draw.SimpleTextOutlined(
					targetEntity:GetModel() or "",
					"RagdollPoserHeaderFont",
					xPos,
					yPos,
					color_white,
					TEXT_ALIGN_LEFT,
					TEXT_ALIGN_BOTTOM,
					OUTLINE_WIDTH,
					BLACK
				)
			end
		elseif IsValid(targetEntity) then
			---@cast entry integer
			local boneName = targetEntity:GetBoneName(entry)
			local color = color_white
			local boneType = RagdollPoser.Bones:GetBoneType(targetEntity, entry)
			if boneType == RagdollPoser.Bones.BoneType.Physics then
				color = GREEN
			elseif boneType == RagdollPoser.Bones.BoneType.Manipulate then
				color = CYAN
			elseif boneType == RagdollPoser.Bones.BoneType.Procedural then
				color = RED
			end

			draw.SimpleTextOutlined(
				boneName,
				"RagdollPoserFont",
				xPos,
				yPos,
				color,
				TEXT_ALIGN_LEFT,
				TEXT_ALIGN_BOTTOM,
				OUTLINE_WIDTH,
				BLACK
			)
		end
	end
end

local scaleVector = Vector(1, 1, 1)
local defaultScaleVector = Vector(1, 1, 1)
function MGR:DrawScaling(mouseHovered)
	local targetEntity = NULL

	for i = 1, #mouseHovered do
		local entry = mouseHovered[i]
		local nextEntry = mouseHovered[i + 1]

		if isentity(entry) then
			---@cast entry Entity
			targetEntity = entry
		elseif IsValid(targetEntity) then
			---@cast entry integer
			local sin = 1 + 0.1 * math.sin(2.666 * math.pi * RealTime())
			scaleVector:SetUnpacked(sin, sin, sin)
			targetEntity:ManipulateBoneScale(entry, scaleVector)
		end
	end
end

function MGR:ResetHoverScale()
	local entities = RagdollPoser.Entity.GetClientEntities()
	for _, entity in ipairs(entities) do
		for b = 0, entity:GetBoneCount() - 1 do
			entity:ManipulateBoneScale(b, defaultScaleVector)
		end
	end
end

function MGR:Render()
	cam.Start2D()
	local mouseHovered = self:DrawBones()
	self:ResetHoverScale()
	self:DrawBoneNames(mouseHovered)
	self:DrawScaling(mouseHovered)
	self:DrawSelected()
	self:DrawHovered()
	cam.End2D()

	cam.Start3D()
	self:Draw()
	cam.End3D()

	-- Draw selected bone
end

local rootResetBone = {}

function MGR:SetTransformFromSelection(selection)
	setPositionFromSelection(selection)
	setAngleFromSelection(selection)
end

local function selected(selection)
	MGR:SetTransformFromSelection(selection)
	MGR:SetEnabled(true)
	RagdollPoser.Selection:SetEnabled(false)
	MGR:OnModeChanged(MGR._mode)
	hovered = {}
	rootResetBone = {}
end
hook.Add("RagdollPoser_Selection_Selected", "Gizmo", selected)

hook.Remove("RagdollPoser_Entity_PostRefresh", "Gizmo")
hook.Add("RagdollPoser_Entity_PostRefresh", "Gizmo", function()
	-- FIXME: I would like to have this run after I get the new client entities. Just doing things these way is really hacky
	-- unless we have hook priorities
	-- timer.Simple(0, function()
	-- 	MGR:SetTransformFromSelection(RagdollPoser.Selection:GetSelection())
	-- end)
end)

local function onKeyPress(actions)
	if MGR:GetMoving() then
		return
	end
	if actions[RagdollPoser.Actions.CycleGizmo] then
		MGR:OnModeChanged(MGR:CycleMode())
	end
	if actions[RagdollPoser.Actions.SelectBone] then
		MGR:SetEnabled(not MGR:IsEnabled())
		RagdollPoser.Selection:SetEnabled(not MGR:IsEnabled())
	end
	if actions[RagdollPoser.Actions.SelectRoot] then
		local selection = RagdollPoser.Selection:GetSelection()
		if not rootResetBone[1] then
			local newestEntity = selection[#selection]
			if IsValid(newestEntity) then
				local rootBone = newestEntity:TranslatePhysBoneToBone(0)
				rootResetBone = { rootBone, newestEntity }
			end
		end

		RagdollPoser.Selection:SetSelection(table.Copy(rootResetBone))
		rootResetBone = table.Copy(selection)
	end
end
hook.Add("RagdollPoser_Input_KeyPress", "Gizmo", onKeyPress)

local function updateHover(state)
	RagdollPoser.Networking.UpdateHovering()
	net.WriteBool(state)
	net.SendToServer()
end
hook.Add("RagdollPoser_Gizmo_Hovering", "UpdateServer", updateHover)
RagdollPoser.Networking.UpdateHovering = RagdollPoser.Networking.DefineSender("UpdateHovering")

function MGR:StartRefreshing()
	self._refreshing = true
end

function MGR:StopRefreshing()
	self._refreshing = false
end

function MGR:IsRefreshing()
	return self._refreshing
end

---@param gizmo string?
local function initializeGizmo(gizmo)
	-- Refresh gizmos
	MGR:StartRefreshing()
	if isstring(gizmo) then
		gizmos[gizmo] = include(Format("ragdollposer/client/gizmos/%s.lua", gizmo))
	else
		gizmos.disc = include("ragdollposer/client/gizmos/disc.lua")
		gizmos.arrow = include("ragdollposer/client/gizmos/arrow.lua")
		gizmos.scale = include("ragdollposer/client/gizmos/scale.lua")
		gizmos.ball = include("ragdollposer/client/gizmos/ball.lua")
		gizmos.sidemove = include("ragdollposer/client/gizmos/sidemove.lua")
		gizmos.sidescale = include("ragdollposer/client/gizmos/sidescale.lua")
		gizmos.omni = include("ragdollposer/client/gizmos/omni.lua")
	end
	MGR:StopRefreshing()
	MGR:UpdateInitializers()

	-- Tool might not initialize the client convars atp so guard against this error
	if GetConVar("ragdollposer_scale") then
		MGR._gizmoProps.scale = GetConVar("ragdollposer_scale"):GetFloat()
		MGR._gizmoProps.width = GetConVar("ragdollposer_width"):GetFloat()
		MGR._gizmoProps.partial = GetConVar("ragdollposer_partial"):GetBool()
		MGR._mirror = GetConVar("ragdollposer_mirror"):GetBool()
		MGR._gizmoProps.orientation = GetConVar("ragdollposer_local"):GetBool() and MGR.Orientation.Local
			or MGR.Orientation.World
		MGR._gizmoProps.localoffset = GetConVar("ragdollposer_localoffset"):GetBool()
		MGR._gizmoProps.relativerotate = GetConVar("ragdollposer_relativerotate"):GetBool()
		MGR._gizmoProps.drawsphere = GetConVar("ragdollposer_drawsphere"):GetBool()
	end
	MGR:UpdateOffset()
	MGR:OnModeChanged(MGR._mode)
end
hook.Remove("CreateMove", "RagdollPoser_InitializeGizmo")
hook.Add("CreateMove", "RagdollPoser_InitializeGizmo", function()
	hook.Remove("CreateMove", "RagdollPoser_InitializeGizmo")
	initializeGizmo()
end)

hook.Remove("RagdollPoser_Gizmo_Refresh", "Gizmo")
hook.Add("RagdollPoser_Gizmo_Refresh", "Gizmo", initializeGizmo)

-- FIXME: Icky boilerplate below. How to improve this?
local function updateWidth(_, old, new)
	local result = tonumber(new)
	if result then
		MGR:SetWidth(result)
	end
end
cvars.RemoveChangeCallback("ragdollposer_width", "ragdollposer_width_callback")
cvars.AddChangeCallback("ragdollposer_width", updateWidth, "ragdollposer_width_callback")
local function updateScale(_, old, new)
	local result = tonumber(new)
	if result then
		MGR:SetScale(result)
	end
end
cvars.RemoveChangeCallback("ragdollposer_scale", "ragdollposer_scale_callback")
cvars.AddChangeCallback("ragdollposer_scale", updateScale, "ragdollposer_scale_callback")
local function updateMirror(_, old, new)
	MGR._mirror = tobool(tonumber(new))
end
cvars.RemoveChangeCallback("ragdollposer_mirror", "ragdollposer_mirror_callback")
cvars.AddChangeCallback("ragdollposer_mirror", updateMirror, "ragdollposer_mirror_callback")

local function updatePartial(_, old, new)
	MGR._gizmoProps.partial = tobool(tonumber(new))
end
cvars.RemoveChangeCallback("ragdollposer_partial", "ragdollposer_partial_callback")
cvars.AddChangeCallback("ragdollposer_partial", updatePartial, "ragdollposer_partial_callback")

local function updateOrientation(_, old, new)
	new = tonumber(new)
	local newOrientation = Either(tobool(new), MGR.Orientation.Local, MGR.Orientation.World)

	MGR._gizmoProps.orientation = newOrientation
	MGR:UpdateOrientation()
end
cvars.RemoveChangeCallback("ragdollposer_local", "ragdollposer_local_callback")
cvars.AddChangeCallback("ragdollposer_local", updateOrientation, "ragdollposer_local_callback")

local function updateRelativeRotate(_, old, new)
	MGR._gizmoProps.relativerotate = tobool(tonumber(new))
end
cvars.RemoveChangeCallback("ragdollposer_relativerotate", "ragdollposer_relativerotate_callback")
cvars.AddChangeCallback("ragdollposer_relativerotate", updateRelativeRotate, "ragdollposer_relativerotate_callback")

local function updateLocalOffset(_, old, new)
	MGR._gizmoProps.localoffset = tobool(tonumber(new))
	MGR:UpdateOffset()
end
cvars.RemoveChangeCallback("ragdollposer_localoffset", "ragdollposer_localoffset_callback")
cvars.AddChangeCallback("ragdollposer_localoffset", updateLocalOffset, "ragdollposer_localoffset_callback")

local function updateDrawSphere(_, old, new)
	MGR._gizmoProps.drawsphere = tobool(tonumber(new))
	MGR:UpdateOffset()
end
cvars.RemoveChangeCallback("ragdollposer_drawsphere", "ragdollposer_drawsphere_callback")
cvars.AddChangeCallback("ragdollposer_drawsphere", updateDrawSphere, "ragdollposer_localoffset_callback")

concommand.Add("ragdollposer_resetgizmo", function()
	initializeGizmo()
end, nil, "Reset the gizmo. Useful for debugging.")

RagdollPoser.Gizmo = MGR
