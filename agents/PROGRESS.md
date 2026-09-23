# Progress

Commit Message: extraArtifacts match anywhere in a path; gradle/kotlin caches refused in subfolders too

Features (Planned):
- Roll the include out to every repo in CodingMain.

Features (Done):
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
