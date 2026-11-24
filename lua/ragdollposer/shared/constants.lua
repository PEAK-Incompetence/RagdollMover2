---[SERVER AND CLIENT]
---
---Dictionary of known values
---
---@class RagdollPoser.Constants
RagdollPoser.Constants = {
	VECTOR_FRONT = Vector(1, 0, 0),
	VECTOR_LEFT = Vector(0, 1, 0),
	VECTOR_ONE = Vector(1, 1, 1),

	MAX_BONE_SIZE = 4,
	MAX_BONE_COLLISION = 20,
	MAX_EDICT_BITS = 13, -- 8192 networked entities limit
	MAX_BONE_BITS = 8, -- 256 bones
	MAX_PHYSBONE_BITS = 5, -- 256 bones
	MAX_ENTITY_LIST_BITS = 10, -- 1024 entities TODO: Should we set this any higher?
}
