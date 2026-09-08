# Ragdoll Mover 2

[![CI](https://github.com/PEAK-Incompetence/RagdollMover2/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/PEAK-Incompetence/RagdollMover2/actions/workflows/ci.yml)

A lot of breaking changes here

## Rational

The old Ragdoll Mover stool is a monolith: all its functionality is contained in a single file, with helpers in different places. For maintainability and preservation purposes, I've decided to create a separate repository to host a new, completely different version of Ragdoll Mover.

The main change between legacy and new versions is [calculating everything on the client](https://github.com/Winded/RagdollMover/issues/40). Currently, the legacy version calculates all transforms on the server. This is a considerable load when given a server with multiple players. With monolith code files, it is risky to make new changes in the legacy version without breaking functionality in multiple places. 

Hence, when we start from a new stool file, we wlil use the legacy version as inspiration for functionality. Rather than storing all the code in a single file, we will split it across multiple files, to improve maintainability and scalability. 

To enhance documentation, we'll also use LuaLS to provide type annotations.
