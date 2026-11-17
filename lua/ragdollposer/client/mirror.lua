local mirrorEnabled = CreateClientConVar(
	"ragdollposer_mirror",
	"0",
	false,
	true,
	"If set to 1, posing on one side will mirror to the other side. This is only supported for bones that are known to mirror each other."
)
local mirrorAxis = CreateClientConVar(
	"ragdollposer_mirror_axis",
	"0",
	false,
	true,
	"If set to 1, posing on one side will mirror to the other side. This is only supported for bones that are known to mirror each other.",
	0,
	2
)

local MGR = {}

---TODO: Allow user-defined mirror patterns
---Odd numbers are left side, even numbers are right side
local mirrorPatterns = {
	"_L",
	"_R", -- TF2,
	"_L_",
	"_R_", -- ValveBiped
	".L",
	".R", -- ValveBiped
	".L.",
	".R.", -- ValveBiped
}

---@param selection table
---@return table mirroredSelection
---@return {[Entity]: {[integer]: integer}} mirroredSet
function MGR:GetMirrored(selection)
	-- Get bones that have a mirror counterpart. Then if our selection also contains that
	-- mirror, then remove it from our mirror
	local mirrorSet = {}
	local mirrored = {}
	for i = 1, #selection - 1, 2 do
		local bone, entity = selection[i], selection[i + 1]
		---@cast bone integer
		---@cast entity Entity
		if mirrorSet[entity] and mirrorSet[entity][bone] then
			continue
		end
		mirrorSet[entity] = mirrorSet[entity] or {}

		local boneName = entity:GetBoneName(bone)
		if boneName then
			for j = 1, #mirrorPatterns - 1, 2 do
				for k = 0, 1 do
					local sideA, sideB = mirrorPatterns[j + k], mirrorPatterns[j + 1 - k]
					local mirror = string.gsub(boneName, sideA, sideB)
					local mirrorBone
					if mirror ~= boneName then
						mirrorBone = entity:LookupBone(mirror)
					end
					-- Avoid double counting our mirrored bones, or else we double transform
					if mirrorBone and not mirrorSet[entity][bone] then
						local index = #mirrored + 1
						mirrored[index] = mirrorBone
						mirrored[index + 1] = entity
						mirrorSet[entity][bone] = mirrorBone
						break
					end
				end
			end
		end
	end

	local deleteMirror = {}
	local count = #mirrored
	for i = 1, count, 2 do
		-- print("current count", count)
		local bone, entity = mirrored[i], mirrored[i + 1]
		local mirrorBone = entity and bone and mirrorSet[entity] and mirrorSet[entity][bone]
		if mirrorBone then
			if mirrorSet[entity][mirrorBone] then
				table.remove(mirrored, i + 1)
				table.remove(mirrored, i)
				count = count - 2
				-- print("removed. new count", count)
				deleteMirror[entity] = deleteMirror[entity] or {}
				deleteMirror[entity][mirrorBone] = true
			elseif deleteMirror[entity] and deleteMirror[mirrorBone] then
				table.remove(mirrored, i + 1)
				table.remove(mirrored, i)
				-- print("removed. new count", count)
				count = count - 2
			end
		end
	end

	return mirrored, mirrorSet
end

function MGR:TransformDelta() end

RagdollPoser.Mirror = MGR
