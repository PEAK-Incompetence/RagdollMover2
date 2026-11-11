---[CLIENT]
---
---Provide additional, cosmetic customization for the user, such as bone colors and client ghost colors
---
---@class RagdollPoser.Themes
local MGR = {}

---@class Theme
local default = {
	-- Gizmo should copy and cache these using the respective `BoneType`
	gizmoColors = {
		physics = Color(0, 255, 0),
		manipulate = Color(0, 128, 255),
		procedural = Color(255, 0, 0),
		selected = Color(255, 255, 0),
		hovered = Color(0, 0, 255),
	},
	clientColor = Color(255, 255, 255),
}

function MGR:Init()
	-- Load current theme (console variable based)
end

function MGR:UpdateTheme()
	hook.Run("RagdollPoser_Themes_Update", self:GetCurrentTheme())
end

function MGR:GetCurrentTheme()
	-- TODO: Allow user to load and save colors for the gizmo and client ghost
	return table.Copy(default)
end

RagdollPoser.Themes = MGR

MGR:Init()
MGR:UpdateTheme()
