local developerCVar = GetConVar("developer")

---@param ... any
local function log(...)
	if developerCVar:GetBool() then
		MsgN("[Ragdoll Poser]: ", ...)
	end
end

RagdollPoser.Log = log
