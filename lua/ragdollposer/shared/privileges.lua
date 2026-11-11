-- CAMI privileges
AddCSLuaFile("sh_cami.lua")
include("sh_cami.lua")

---@class RagdollPoser.Privileges
---@field Players table<Player, table<string, boolean>>
---@field List table<string, CAMI_PRIVILEGE>
RagdollPoser.Privileges = RagdollPoser.Privileges or {}

RagdollPoser.Privileges.Players = RagdollPoser.Privileges.Players or {}

RagdollPoser.Privileges.List = {
	ragdollposer_xray = {
		Name = "ragdollposer_xray",
		MinAccess = "admin",
		Description = "Allow users to select or manipulate entities through walls",
	},
}

---@param ply Player
---@param privilege string
---@return boolean
function RagdollPoser.Privileges:Check(ply, privilege)
	return self.Players[ply][privilege]
end

if not CAMI then
	return
end

local function updatePrivileges(ply)
	RagdollPoser.Privileges.Players[ply] = RagdollPoser.Privileges.Players[ply] or {}
	for name, _ in pairs(RagdollPoser.Privileges.List) do
		CAMI.PlayerHasAccess(ply, name, function(hasAccess, reason)
			RagdollPoser.Privileges.Players[ply][name] = hasAccess
		end)
	end

	--- Refresh player's control panel if they have access`
	if SERVER then
		return
	end
	local tool = ply:GetTool("ragdollposer")
	---@cast tool TOOL?
	if tool then
		tool:RebuildControlPanel()
	end
end

hook.Add("SetupMove", "rgmReportPrivileges", function(pl)
	if not RagdollPoser.Privileges.Players[pl] then
		RagdollPoser.Privileges.Players[pl] = {}
		updatePrivileges(pl)
	end
end)

hook.Add("PlayerDisconnected", "rgmClearPrivileges", function(ply)
	RagdollPoser.Privileges.Players[ply] = nil
end)

hook.Add("CAMI.PlayerUsergroupChanged", "rgmUpdatePrivileges", updatePrivileges)

function RagdollPoser.Privileges:Init()
	for name, privilege in pairs(RagdollPoser.Privileges.List) do
		CAMI.RegisterPrivilege(privilege)
	end

	for _, ply in ipairs(player.GetAll()) do
		updatePrivileges(ply)
	end
end

RagdollPoser.Privileges:Init()
timer.Simple(0, function()
	RagdollPoser.Privileges:Init()
end)
