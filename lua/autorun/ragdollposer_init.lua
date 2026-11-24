RagdollPoser = RagdollPoser or {}
RagdollPoser.Mode = "ragdollposer"
RagdollPoser.ConstraintTypeBits = 7
RagdollPoser.ConstraintBits = 32

---Keep these constraint type orders fixed
---@enum ConstraintType
RagdollPoser.ConstraintTypes = {
	bonemerge = 0,
	ik = 1,
	lockang = 2,
	lockbone = 3,
	lockpos = 4,
	lockscale = 5,
}
RagdollPoser.TypeConstraints = table.Flip(RagdollPoser.ConstraintTypes)

local root = "ragdollposer/"

local folderFilter = {
	["constraints"] = true,
	["gizmos"] = true,
}

---Recursive include from https://github.com/2048khz-gachi-rmx/ImprovedAdminPhysgun/blob/7774d0f4ca70818adebe2718c37238784f25efae/lua/autorun/pgun_impr.lua#L6
---@param sub string
---@param cl boolean?
---@param sv boolean?
local function recInc(sub, cl, sv)
	local path = (root .. sub):gsub("/$", "") .. "/" -- force a / at the end

	local shouldInc = CLIENT and (cl == nil or cl) or SERVER and (sv == nil or sv)

	local shouldShare = SERVER and (cl == nil or cl)

	local files, folders = file.Find(path .. "*", "LUA")
	for _, folder in ipairs(folders) do
		if not folderFilter[folder] then
			recInc(sub .. "/" .. folder, cl, sv)
		end
	end

	for k, v in ipairs(files) do
		---@type string
		local fn = path .. v
		if fn:match("/_.+%.lua$") then
			continue
		end -- ignore lua files starting with _

		if shouldInc then
			include(fn)
		end

		if shouldShare then
			AddCSLuaFile(fn)
		end
	end
end

local function initialize()
	recInc("shared", true, true) -- everything in root is shared
	recInc("server", false, true)
	recInc("client", true, false)
end

initialize()
initialize()

concommand.Add("ragdollposer_initialize", function()
	initialize()
	initialize()
end, nil, "Re-initialize the client systems")
