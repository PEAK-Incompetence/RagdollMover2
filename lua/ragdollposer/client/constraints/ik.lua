-- Vibecoded the Jacobian IK Solver with GPT-6 Luna
-- It works surprisingly well

---@class IKConstraint: Constraint
---@field State IKConstraintState
local ik = include("base.lua")

local MAX_ITERATIONS = 64
-- This is the amount of precision to give to IKs.
-- Is this a reasonable value? Would it be bad if I set it lower?
local POSITION_EPSILON = 0.001
local DAMPING = 0.15
local MAX_STEP = math.rad(8)
local MAX_REACH_FRACTION = 0.9975
local LINE_COLOR = Color(0, 220, 255, 255)
local IDENTITY_MATRIX = Matrix()
IDENTITY_MATRIX:Identity()

local function isFiniteNumber(value)
	return isnumber(value) and value == value and value ~= math.huge and value ~= -math.huge
end

local function isFiniteVector(vector)
	return vector and isFiniteNumber(vector.x) and isFiniteNumber(vector.y) and isFiniteNumber(vector.z)
end

local function isFiniteAngle(angle)
	return angle and isFiniteNumber(angle.p) and isFiniteNumber(angle.y) and isFiniteNumber(angle.r)
end

local function isFiniteMatrix(matrix)
	if not matrix then
		return false
	end

	for row = 1, 4 do
		for column = 1, 4 do
			if not isFiniteNumber(matrix:GetField(row, column)) then
				return false
			end
		end
	end

	return true
end

local function matrixTransformChanged(matrix, baseline)
	if not isFiniteMatrix(matrix) or not isFiniteMatrix(baseline) then
		return false
	end

	if (matrix:GetTranslation() - baseline:GetTranslation()):LengthSqr() > 1e-6 then
		return true
	end

	local angles = matrix:GetAngles()
	local baselineAngles = baseline:GetAngles()
	if
		math.abs(math.AngleDifference(angles.p, baselineAngles.p)) > 0.01
		or math.abs(math.AngleDifference(angles.y, baselineAngles.y)) > 0.01
		or math.abs(math.AngleDifference(angles.r, baselineAngles.r)) > 0.01
	then
		return true
	end

	return (matrix:GetScale() - baseline:GetScale()):LengthSqr() > 1e-8
end

ik.Properties = {
	type = "ik",
	category = "#tool.ragdollposer.constraint.category.tracking",
	name = "#tool.ragdollposer.constraint.ik.name",
	desc = "#tool.ragdollposer.constraint.ik.desc",
	help = "#tool.ragdollposer.constraint.ik.help",
	short = "#tool.ragdollposer.constraint.ik.short",
}

---@class IKConstraintState: ConstraintState
---@field iterations integer
---@field length integer Number of parent links above the end effector
---@field offset Vector World-space end-effector offset
---@field weightPosition boolean
---@field weightPositionValue number
---@field weightRotation boolean
---@field weightRotationValue number
---@field weightRotationConfigured boolean?
ik.State = table.Merge(table.Copy(ik.State), {
	iterations = 32,
	length = 2,
	offset = Vector(),
	weightPosition = true,
	weightPositionValue = 1,
	weightRotation = true,
	weightRotationValue = 1,
})

local function makeChain(entity, effector, parentLinks)
	local chain = {}
	local bone = effector

	for _ = 0, parentLinks do
		if bone < 0 then
			break
		end
		chain[#chain + 1] = bone
		bone = entity:GetBoneParent(bone)
	end

	return chain
end

local function isDescendant(entity, bone, ancestor)
	local walk = bone
	while walk and walk >= 0 do
		if walk == ancestor then
			return true
		end
		walk = entity:GetBoneParent(walk)
	end
	return false
end

local function applyJointRotation(transforms, subtree, jointBone, axis, degrees, saveMatrix)
	if not isFiniteNumber(degrees) or not isFiniteVector(axis) then
		return false, "non-finite joint rotation"
	end
	if math.abs(degrees) < 1e-5 then
		return true
	end

	local jointMatrix = transforms[jointBone + 1]
	if not isFiniteMatrix(jointMatrix) then
		return false, "non-finite joint matrix"
	end

	local axisLength = axis:Length()
	if not isFiniteNumber(axisLength) or axisLength <= 1e-10 then
		return false, "invalid joint rotation axis"
	end

	axis:Normalize()
	if not isFiniteVector(axis) then
		return false, "non-finite normalized rotation axis"
	end

	local pivot = jointMatrix:GetTranslation()
	local rotation = Angle(0, 0, 0)
	rotation:RotateAroundAxis(axis, degrees)
	if not isFiniteAngle(rotation) then
		return false, "non-finite joint angle"
	end

	for _, matrixIndex in ipairs(subtree) do
		local matrix = transforms[matrixIndex]
		if matrix then
			if not isFiniteMatrix(matrix) then
				return false, "non-finite subtree matrix"
			end

			local position = matrix:GetTranslation()
			local relative = position - pivot
			relative:Rotate(rotation)
			local rotatedPosition = pivot + relative

			local angles = matrix:GetAngles()
			angles:RotateAroundAxis(axis, degrees)
			if not isFiniteVector(rotatedPosition) or not isFiniteAngle(angles) then
				return false, "non-finite rotated transform"
			end

			saveMatrix(matrixIndex)
			matrix:SetTranslation(rotatedPosition)
			matrix:SetAngles(angles)
			if not isFiniteMatrix(matrix) then
				return false, "non-finite rotated matrix"
			end
		end
	end

	return true
end

local function solveSymmetric3(a, b, c, rhs)
	if not isFiniteVector(a) or not isFiniteVector(b) or not isFiniteVector(c) or not isFiniteVector(rhs) then
		return nil, "non-finite solver input"
	end

	local crossBC = b:Cross(c)
	if not isFiniteVector(crossBC) then
		return nil, "non-finite determinant input"
	end

	local determinant = a:Dot(crossBC)
	if not isFiniteNumber(determinant) then
		return nil, "non-finite determinant"
	end
	if math.abs(determinant) < 1e-10 then
		return nil
	end

	local response =
		Vector(rhs:Dot(crossBC) / determinant, rhs:Dot(c:Cross(a)) / determinant, rhs:Dot(a:Cross(b)) / determinant)
	if not isFiniteVector(response) then
		return nil, "non-finite solver response"
	end

	return response
end

local function solvePosition(entity, transforms, chain, goal, iterations, influence, saveMatrix)
	local endEffector = chain[1]
	local effectorMatrix = transforms[endEffector + 1]
	if not effectorMatrix then
		return false, "missing effector matrix", endEffector
	end
	if not isFiniteVector(goal) then
		return false, "non-finite goal", endEffector
	end
	if not isFiniteMatrix(effectorMatrix) then
		return false, "non-finite effector matrix", endEffector
	end
	if not isFiniteNumber(influence) then
		return false, "non-finite influence", endEffector
	end

	local maxReach = 0
	for chainIndex = 1, #chain - 1 do
		local child = transforms[chain[chainIndex] + 1]
		local parent = transforms[chain[chainIndex + 1] + 1]
		if child and parent then
			if not isFiniteMatrix(child) or not isFiniteMatrix(parent) then
				return false, "non-finite chain matrix", chain[chainIndex]
			end

			local segmentLength = child:GetTranslation():Distance(parent:GetTranslation())
			if not isFiniteNumber(segmentLength) then
				return false, "non-finite chain length", chain[chainIndex]
			end
			maxReach = maxReach + segmentLength
			if not isFiniteNumber(maxReach) then
				return false, "non-finite maximum reach", chain[chainIndex]
			end
		end
	end
	local rootMatrix = transforms[chain[#chain] + 1]
	if maxReach > 0 then
		if not isFiniteMatrix(rootMatrix) then
			return false, "non-finite root matrix", chain[#chain]
		end

		local rootPosition = rootMatrix:GetTranslation()
		local goalOffset = goal - rootPosition
		local goalDistance = goalOffset:Length()
		local reachableDistance = maxReach * MAX_REACH_FRACTION
		if
			not isFiniteVector(goalOffset)
			or not isFiniteNumber(goalDistance)
			or not isFiniteNumber(reachableDistance)
		then
			return false, "non-finite reach calculation", chain[#chain]
		end

		if goalDistance > reachableDistance then
			if goalDistance <= 0 then
				return false, "invalid reach distance", chain[#chain]
			end

			local reachScale = reachableDistance / goalDistance
			if not isFiniteNumber(reachScale) then
				return false, "non-finite reach scale", chain[#chain]
			end
			goal = rootPosition + goalOffset * reachScale
			if not isFiniteVector(goal) then
				return false, "non-finite clamped goal", chain[#chain]
			end
		end
	end

	local subtrees = {}
	for chainIndex = 2, #chain do
		local joint = chain[chainIndex]
		local subtree = {}
		for bone = 0, entity:GetBoneCount() - 1 do
			local matrixIndex = bone + 1
			if isDescendant(entity, bone, joint) then
				subtree[#subtree + 1] = matrixIndex
			end
		end
		subtrees[joint] = subtree
	end

	for iteration = 1, iterations do
		effectorMatrix = transforms[endEffector + 1]
		if not isFiniteMatrix(effectorMatrix) then
			return false, "non-finite effector matrix", endEffector, iteration
		end

		local error = goal - effectorMatrix:GetTranslation()
		local errorLengthSqr = error:LengthSqr()
		if not isFiniteVector(error) or not isFiniteNumber(errorLengthSqr) then
			return false, "non-finite position error", endEffector, iteration
		end
		if errorLengthSqr <= POSITION_EPSILON * POSITION_EPSILON then
			break
		end

		local columns = {}
		local xx, xy, xz, yy, yz, zz = 0, 0, 0, 0, 0, 0

		for chainIndex = 2, #chain do
			local joint = chain[chainIndex]
			local jointMatrix = transforms[joint + 1]
			if jointMatrix then
				if not isFiniteMatrix(jointMatrix) then
					return false, "non-finite joint matrix", joint, iteration
				end

				local pivot = jointMatrix:GetTranslation()
				local offset = effectorMatrix:GetTranslation() - pivot
				if not isFiniteVector(offset) then
					return false, "non-finite joint offset", joint, iteration
				end

				local axes = {
					jointMatrix:GetForward(),
					jointMatrix:GetRight(),
					jointMatrix:GetUp(),
				}

				for _, axis in ipairs(axes) do
					local axisLength = axis:Length()
					if not isFiniteNumber(axisLength) or axisLength <= 1e-10 then
						return false, "invalid joint basis axis", joint, iteration
					end
					axis:Normalize()
					if not isFiniteVector(axis) then
						return false, "non-finite normalized basis axis", joint, iteration
					end

					local column = axis:Cross(offset)
					if not isFiniteVector(column) then
						return false, "non-finite Jacobian column", joint, iteration
					end

					columns[#columns + 1] = {
						bone = joint,
						axis = axis,
						column = column,
					}
					xx = xx + column.x * column.x
					xy = xy + column.x * column.y
					xz = xz + column.x * column.z
					yy = yy + column.y * column.y
					yz = yz + column.y * column.z
					zz = zz + column.z * column.z
				end
			end
		end

		if #columns == 0 then
			break
		end

		local dampingSquared = DAMPING * DAMPING
		local response, solveError = solveSymmetric3(
			Vector(xx + dampingSquared, xy, xz),
			Vector(xy, yy + dampingSquared, yz),
			Vector(xz, yz, zz + dampingSquared),
			error
		)
		if solveError then
			return false, solveError, endEffector, iteration
		end
		if not response then
			break
		end

		local updates, jointOrder = {}, {}
		for _, column in ipairs(columns) do
			local radians = column.column:Dot(response) * influence
			if not isFiniteNumber(radians) then
				return false, "non-finite joint response", column.bone, iteration
			end

			local update = updates[column.bone]
			if not update then
				update = { axis = Vector() }
				updates[column.bone] = update
				jointOrder[#jointOrder + 1] = column.bone
			end
			update.axis:Add(column.axis * radians)
			if not isFiniteVector(update.axis) then
				return false, "non-finite accumulated rotation", column.bone, iteration
			end
		end

		for _, joint in ipairs(jointOrder) do
			local update = updates[joint]
			local radians = update.axis:Length()
			if not isFiniteNumber(radians) then
				return false, "non-finite rotation magnitude", joint, iteration
			end
			if radians > MAX_STEP then
				local scale = MAX_STEP / radians
				if not isFiniteNumber(scale) then
					return false, "non-finite rotation scale", joint, iteration
				end
				update.axis:Mul(scale)
				if not isFiniteVector(update.axis) then
					return false, "non-finite clamped rotation", joint, iteration
				end
				radians = MAX_STEP
			end
			if radians > 1e-5 then
				local applied, rotationError =
					applyJointRotation(transforms, subtrees[joint], joint, update.axis, math.deg(radians), saveMatrix)
				if not applied then
					return false, rotationError, joint, iteration
				end
			end
		end
	end

	return true
end

function ik:ConstructUI(entry, props, state)
	self.State.target = self.Owner
	entry.Header:SetTooltip("#tool.ragdollposer.constraint.ik.help")

	local ui, header, footer = self:ConstructUITemplate(entry, props or self.Properties, self.State)
	header()
	ui.target:SetEnabled(false)
	ui.target:SetTooltip("#tool.ragdollposer.constraint.ik.owner")

	ui.length = entry:NumSlider("#tool.ragdollposer.constraint.ik.length", "", 1, 16, 0)
	ui.length:SetValue(self.State.length)
	function ui.length.OnValueChanged(_, value)
		self.State.length = math.max(math.floor(value), 1)
		RagdollPoser.Constraints:UpdateConstraint(self.Owner, self)
	end

	ui.iterations = entry:NumSlider("#tool.ragdollposer.constraint.ik.iterations", "", 1, MAX_ITERATIONS, 0)
	ui.iterations:SetValue(self.State.iterations)
	function ui.iterations.OnValueChanged(_, value)
		self.State.iterations = math.Clamp(math.floor(value), 1, MAX_ITERATIONS)
		RagdollPoser.Constraints:UpdateConstraint(self.Owner, self)
	end

	self.State.offset = self.State.offset or Vector()
	for axis, label in ipairs({
		"#tool.ragdollposer.constraint.ik.offset.x",
		"#tool.ragdollposer.constraint.ik.offset.y",
		"#tool.ragdollposer.constraint.ik.offset.z",
	}) do
		local control = entry:NumSlider(label, "", -32, 32, 1)
		control:SetValue(self.State.offset[axis])
		control.OnValueChanged = function(_, value)
			self.State.offset[axis] = value
			RagdollPoser.Constraints:UpdateConstraint(self.Owner, self)
		end
		ui["offset" .. axis] = control
	end

	ui.weightPosition = entry:NumSlider("#tool.ragdollposer.constraint.ik.positionweight", "", 0, 1, 2)
	ui.weightPosition:SetValue(self.State.weightPositionValue or 1)
	function ui.weightPosition.OnValueChanged(_, value)
		self.State.weightPositionValue = value
		RagdollPoser.Constraints:UpdateConstraint(self.Owner, self)
	end

	ui.weightRotation = vgui.Create("DCheckBoxLabel", entry)
	ui.weightRotation:SetText(language.GetPhrase("#tool.ragdollposer.constraint.ik.rotationweight"))
	ui.weightRotation:SetChecked(self.State.weightRotation ~= false)
	ui.weightRotation:SizeToContents()
	function ui.weightRotation.OnChange(_, enabled)
		self.State.weightRotation = enabled
		self.State.weightRotationConfigured = true
		ui.rotationWeight:SetEnabled(enabled)
		RagdollPoser.Constraints:UpdateConstraint(self.Owner, self)
	end
	entry:AddItem(ui.weightRotation)

	ui.rotationWeight = entry:NumSlider("#tool.ragdollposer.constraint.ik.rotationweight.value", "", 0, 1, 2)
	ui.rotationWeight:SetValue(self.State.weightRotationValue or 1)
	ui.rotationWeight:SetEnabled(self.State.weightRotation ~= false)
	function ui.rotationWeight.OnValueChanged(_, value)
		self.State.weightRotationValue = value
		self.State.weightRotationConfigured = true
		RagdollPoser.Constraints:UpdateConstraint(self.Owner, self)
	end

	footer()
end

function ik:PreEvaluate(entity, transforms, indices, locals, parents)
	self._goal = nil
	self._poseLocals = nil
	self._effectorLocal = nil
	self._effectorAngles = nil
	self._invalidSolveLogged = nil

	if
		self.State.enabled == false
		or entity ~= self.Owner
		or self.State.target ~= self.Owner
		or self.State.weightPosition == false
		or not IsValid(entity)
	then
		return
	end

	local effector = self.State.bone
	local client = RagdollPoser.Entity:GetClientFromEntity(entity)
	if not IsValid(client) or not isnumber(effector) or effector < 0 or effector >= client:GetBoneCount() then
		return
	end

	RagdollPoser.Entity:ExposeBones(client)
	local matrices = RagdollPoser.Entity:GetMatricesFromClient(client)
	local matrix = matrices and matrices[effector + 1]
	if not matrix then
		return
	end

	local offset = self.State.offset or vector_origin
	self._goal = matrix:GetTranslation() + offset
	self._effectorAngles = matrix:GetAngles()
	self._poseLocals = {}
	for bone = 0, client:GetBoneCount() - 1 do
		local parent = client:GetBoneParent(bone)
		local childMatrix = matrices[bone + 1]
		local parentMatrix = parent >= 0 and matrices[parent + 1]
		if childMatrix and parentMatrix then
			self._poseLocals[bone] = parentMatrix:GetInverse() * childMatrix
		end
	end
	if client:GetBoneParent(effector) >= 0 then
		self._effectorLocal = self._poseLocals[effector]
	else
		self._effectorLocal = matrix * IDENTITY_MATRIX
	end

	local chain = makeChain(client, effector, math.Clamp(math.floor(self.State.length or 1), 1, 16))
	if #chain < 2 then
		return
	end

	local affectedBones = {}
	local root = chain[#chain]
	for bone = 0, client:GetBoneCount() - 1 do
		if isDescendant(client, bone, root) then
			affectedBones[#affectedBones + 1] = bone
		end
	end
	return affectedBones
end

function ik:EvaluatePose(entity, context)
	local transforms = context and context.transforms
	local selectedBoneMatrices = context and context.selectedBoneMatrices
	local forceCurrentGoal = context and context.forceCurrentGoal
	if
		self.State.enabled == false
		or self.State.weightPosition == false
		or entity ~= self.Owner
		or self.State.target ~= self.Owner
		or not context
		or not self._goal
		or not self._poseLocals
		or not self._effectorLocal
		or not transforms
	then
		return
	end

	-- FIXME: Descendant bones of a bone that has IK are locked in position.
	-- These should be movable
	local client = RagdollPoser.Entity:GetClientFromEntity(entity)
	if not IsValid(client) then
		return
	end

	local effector = self.State.bone
	local effectorMatrix = transforms[effector + 1]
	if not effectorMatrix then
		return
	end

	local backups = {}
	local function saveMatrix(matrixIndex)
		local matrix = transforms[matrixIndex]
		if not backups[matrixIndex] and matrix then
			backups[matrixIndex] = {
				original = matrix,
				copy = matrix * IDENTITY_MATRIX,
			}
		end
	end

	local function abortSolve(reason, bone, iteration)
		for matrixIndex, backup in pairs(backups) do
			backup.original:Set(backup.copy)
			transforms[matrixIndex] = backup.original
		end

		if not self._invalidSolveLogged then
			RagdollPoser.Log(
				"IK solve aborted: ",
				reason,
				" on ",
				entity,
				" effector ",
				effector,
				" bone ",
				bone or "n/a",
				" iteration ",
				iteration or "n/a"
			)
			self._invalidSolveLogged = true
		end
	end

	if not isFiniteMatrix(effectorMatrix) then
		abortSolve("non-finite effector matrix", effector)
		return
	end

	local parent = client:GetBoneParent(effector)
	local selectedEffector = forceCurrentGoal == true
		or (selectedBoneMatrices and selectedBoneMatrices[effector] ~= nil)
	if not selectedEffector then
		local currentEffectorLocal = effectorMatrix
		if parent >= 0 then
			local parentMatrix = transforms[parent + 1]
			if isFiniteMatrix(parentMatrix) then
				currentEffectorLocal = parentMatrix:GetInverse() * effectorMatrix
			end
		end
		selectedEffector = matrixTransformChanged(currentEffectorLocal, self._effectorLocal)
	end

	local offset = self.State.offset or vector_origin
	if not isFiniteVector(offset) or not isFiniteVector(self._goal) or not isFiniteAngle(self._effectorAngles) then
		abortSolve("non-finite IK goal input", effector)
		return
	end

	local goal = selectedEffector and (effectorMatrix:GetTranslation() + offset) or self._goal
	if not isFiniteVector(goal) then
		abortSolve("non-finite IK goal", effector)
		return
	end

	local chain = makeChain(client, effector, math.Clamp(math.floor(self.State.length or 1), 1, 16))
	if #chain < 2 then
		return
	end

	local influenceValue = self.State.influence or 1
	local positionWeight = self.State.weightPositionValue or 1
	if not isFiniteNumber(influenceValue) or not isFiniteNumber(positionWeight) then
		abortSolve("non-finite position weight", effector)
		return
	end

	local influence = math.Clamp(influenceValue, 0, 1) * math.Clamp(positionWeight, 0, 1)
	if not isFiniteNumber(influence) then
		abortSolve("non-finite position influence", effector)
		return
	end
	if influence == 0 then
		return
	end

	local effectorAngles = selectedEffector and effectorMatrix:GetAngles() or self._effectorAngles
	if not isFiniteAngle(effectorAngles) then
		abortSolve("non-finite effector angles", effector)
		return
	end

	if parent >= 0 then
		local parentMatrix = transforms[parent + 1]
		if parentMatrix then
			if not isFiniteMatrix(parentMatrix) or not isFiniteMatrix(self._effectorLocal) then
				abortSolve("non-finite effector restore input", effector)
				return
			end

			local restored = parentMatrix * self._effectorLocal
			restored:SetAngles(effectorAngles)
			if not isFiniteMatrix(restored) then
				abortSolve("non-finite restored effector", effector)
				return
			end

			saveMatrix(effector + 1)
			transforms[effector + 1] = restored
		end
	else
		if not isFiniteMatrix(self._effectorLocal) then
			abortSolve("non-finite effector local", effector)
			return
		end

		local restored = self._effectorLocal * IDENTITY_MATRIX
		restored:SetAngles(effectorAngles)
		if not isFiniteMatrix(restored) then
			abortSolve("non-finite restored effector", effector)
			return
		end

		saveMatrix(effector + 1)
		transforms[effector + 1] = restored
	end

	local function propagate(bone)
		local parentMatrix = transforms[bone + 1]
		if not parentMatrix then
			return true
		end
		if not isFiniteMatrix(parentMatrix) then
			return false, "non-finite propagation parent", bone
		end
		---@cast parentMatrix VMatrix
		for _, child in ipairs(client:GetChildBones(bone)) do
			local localMatrix = self._poseLocals[child]
			local childIndex = child + 1
			if localMatrix and transforms[childIndex] then
				if not isFiniteMatrix(transforms[childIndex]) or not isFiniteMatrix(localMatrix) then
					return false, "non-finite propagation input", child
				end

				local childMatrix = parentMatrix * localMatrix
				if not isFiniteMatrix(childMatrix) then
					return false, "non-finite propagated matrix", child
				end

				saveMatrix(childIndex)
				transforms[childIndex] = childMatrix
				local propagated, reason, failedBone = propagate(child)
				if not propagated then
					return false, reason, failedBone
				end
			end
		end
		return true
	end

	local propagated, propagationError, propagationBone = propagate(effector)
	if not propagated then
		abortSolve(propagationError, propagationBone)
		return
	end

	local iterations = math.Clamp(math.floor(self.State.iterations or 32), 1, MAX_ITERATIONS)
	local solved, solveError, failedBone, failedIteration =
		solvePosition(client, transforms, chain, goal, iterations, influence, saveMatrix)
	if not solved then
		abortSolve(solveError, failedBone, failedIteration)
		return
	end

	local rotationInfluence = 0
	if self.State.weightRotation ~= false then
		local rotationWeight = self.State.weightRotationValue or 1
		if not isFiniteNumber(influenceValue) or not isFiniteNumber(rotationWeight) then
			abortSolve("non-finite rotation weight", effector)
			return
		end
		rotationInfluence = math.Clamp(influenceValue, 0, 1) * math.Clamp(rotationWeight, 0, 1)
	end
	if not isFiniteNumber(rotationInfluence) then
		abortSolve("non-finite rotation influence", effector)
		return
	end

	if rotationInfluence > 0 then
		effectorMatrix = transforms[effector + 1]
		if effectorMatrix then
			if not isFiniteMatrix(effectorMatrix) then
				abortSolve("non-finite solved effector", effector)
				return
			end

			local angles = LerpAngle(rotationInfluence, effectorMatrix:GetAngles(), effectorAngles)
			if not isFiniteAngle(angles) then
				abortSolve("non-finite blended effector angle", effector)
				return
			end

			saveMatrix(effector + 1)
			effectorMatrix:SetAngles(angles)
			if not isFiniteMatrix(effectorMatrix) then
				abortSolve("non-finite rotated effector", effector)
				return
			end

			propagated, propagationError, propagationBone = propagate(effector)
			if not propagated then
				abortSolve(propagationError, propagationBone)
				return
			end
		end
	end

	for matrixIndex in pairs(backups) do
		if not isFiniteMatrix(transforms[matrixIndex]) then
			abortSolve("non-finite final matrix", matrixIndex - 1)
			return
		end
	end
end

function ik:GetOutputRoot()
	local effector = self.State.bone
	if
		self.State.enabled == false
		or self.State.weightPosition == false
		or self.State.target ~= self.Owner
		or not IsValid(self.Owner)
		or not isnumber(effector)
		or effector < 0
		or effector >= self.Owner:GetBoneCount()
	then
		return nil
	end

	local chain = makeChain(self.Owner, effector, math.Clamp(math.floor(self.State.length or 1), 1, 16))
	return chain[#chain]
end

function ik:Draw()
	local effector = self.State.bone
	if
		self.State.enabled == false
		or self.State.weightPosition == false
		or self.State.target ~= self.Owner
		or not IsValid(self.Owner)
		or not isnumber(effector)
		or effector < 0
	then
		return
	end

	local client = RagdollPoser.Entity:GetClientFromEntity(self.Owner)
	if not IsValid(client) or effector >= client:GetBoneCount() then
		return
	end

	local chain = makeChain(client, effector, math.Clamp(math.floor(self.State.length or 1), 1, 16))
	if #chain < 2 then
		return
	end

	local matrices = RagdollPoser.Entity:GetMatricesFromClient(client)
	if not matrices then
		return
	end

	render.SetColorMaterialIgnoreZ()
	for index = 1, #chain - 1 do
		local child = matrices[chain[index] + 1]
		local parent = matrices[chain[index + 1] + 1]
		if child and parent then
			render.DrawLine(child:GetTranslation(), parent:GetTranslation(), LINE_COLOR, false)
		end
	end
end

local function createConstraint(entity, state, name)
	local base = ik:Init(entity, state, name)
	---@cast base IKConstraint
	base.State.target = base.Owner
	if not base.State.weightRotationConfigured then
		base.State.weightRotation = true
		base.State.weightRotationConfigured = true
	end
	return base
end

if RagdollPoser.Constraints and not RagdollPoser.Constraints:IsRefreshing() then
	hook.Run("RagdollPoser_Constraints_Refresh", ik.Properties.type)
end

return createConstraint
