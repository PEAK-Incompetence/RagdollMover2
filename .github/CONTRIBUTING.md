# Contributing to RagdollMover2

## Pull Requests

Read the [Staging and Production](https://github.com/PEAK-Incompetence/RagdollMover2/discussions/1) overview to get up to speed with how we PR things.

### Coding conventions

This project uses `glua_check` from [gmod-glua-ls](https://github.com/Pollux12/gmod-glua-ls) to perform linting. On push and pull request, it runs a CI workflow to catch errors and warnings.

If you are not using VSCode, read this portion of the [linter repository](https://github.com/Pollux12/gmod-glua-ls#other-editors). Then you need to run the following command in your terminal before making a commit:

```bash
glua_check . --gmod-annotations path/to/gmod/annotations
```

(where the path leads to a generated annotations folder, found when first running `gmod_lua.exe` binary).

It is your responsibility to use this tool to catch linting errors. You should also try to minimize lint warnings as much as possible.

This project uses [StyLua](https://github.com/JohnnyMorganz/StyLua) for formatting. The repository comes with a `.stylua.toml` to guide the formatter.
