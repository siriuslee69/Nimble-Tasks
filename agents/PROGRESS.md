# Progress

Commit Message: preset.nims: build presets from configs/*.toml, -d:preset forwarded by every shared task

Features (Planned):
- Roll the include out to every repo in CodingMain.

Features (Done):
- preset.nims (2026-09-23): configs/default.toml always, -d:preset=<name>
  laid over it key by key, the command line over both. [nim] [define]
  [passC] [passL] become compiler switches; other sections are left for the
  program and nix. `projectValue` reads [project] for the .nimble file.
  Shared tasks forward -d:preset= to nim (presetFlag in core.nims).
  Tested by four new cases in test_shared_tasks.
- One include file with 28 shared tasks, each skippable through `ownTasks`.
- Hint line before every task (shared vs. the repo's own).
- Frontend entry lookup over the usual places; stops with every place it looked.
- `updateSubmodules` pins every submodule to its newest main commit.
- Integration test that builds throwaway repos and drives real nimble.

Features (In Progress):
- Rollout: Proto-RepoTemplate, Eir, Tyr, Bifrost, SIMD-Nexus, Fylgia, Otter, Eris.

Notes:
- Last problem encountered: `gorgeEx` runs in the folder of the file that
  calls it, so git commands ran in Nimble-Tasks instead of the calling repo.
- Fix: every git call goes through `gitRaw`, which adds `-C <repo folder>`.
  The integration test caught it and now passes (11/11).
