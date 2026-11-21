# Progress

Commit Message: Retry GTK tasks from an existing Nix shell when GTK4 is missing

## GTK shell handoff for MimicWidgets

`nimble runOwlLab` used to skip the project shell whenever `IN_NIX_SHELL`
was set. The shared launcher checks for GTK inside existing Nix shells too.
The retry is marked for that project and reports an error if GTK4 is still
missing. Tested the retry, the working environment, and the broken project
shell in `nimble test`. Opened and closed the real lab from a Nix shell
with `pkg-config` and no GTK4.

## Earlier work

2026-11-20: `enterGtkShell()` (frontends.nims). Trigger: plain `nimble runOwl` in MimicWidgets died at
the link step (`ld: cannot find harfbuzz`) because the user's session sets PKG_CONFIG_PATH to some GTK
folders but not harfbuzz. The task now checks `pkg-config --exists gtk4`; when it fails, and the repo
has an owl entry and a shell file (`nixShell` const, else nix/owlkettle-shell.nix, else nix/shell.nix),
and IN_NIX_SHELL is empty, nix-shell exists and no `nimCommand` is set, it runs the same nimble call
(`calledParams()` keeps the arguments) inside `nix-shell <file> --run`. It RETURNS true instead of
calling `quit`: a `quit(0)` inside a task makes nimble print "Failed to execute task". Repo-own
tasks call it as `if enterGtkShell(): return`. Tests: suite "GTK shell hop" (fake nix-shell and
pkg-config first on PATH; hop, no hop inside a shell, no hop when GTK is visible, no hop without a
window). Checked for real: MimicWidgets `nimble runOwl` (window up), `nimble previewGallery` (exit 0).
Not changed: repos that set `nimCommand` (Atlas-PackageManager) keep their own wrapper.
Also: `examples/example_useSharedTasks.nim` (the repo had no example): writes a one-file repo into
build/example_demo/ and calls `runCli` and `sharedTasks` on it; run by `nimble runExamples`.

2026-11-19: `runStress` runs `evaluation/stress/**/attack*.nim` and `stress*.nim` the same
way `runTests` runs tests (built together, run one at a time). `programsIn` takes several
prefixes joined with `|`. A soak lives below `evaluation/stress/soak/` under another name and
keeps its own task. NOT run by the author: no repo has been built against the new task yet
(Nebel, Bifrost and Fjord are moved in the same session; their first `nimble runStress` is
the test).

Features (Planned):
- Roll the include out to every repo in CodingMain.

Features (Done):
- Optional `nimCommand` routes frontend and evaluation builds through a repo's dependency environment. Defaults to `nim`; integration coverage builds and runs an actual wrapper fixture.
- runTests/test/runBenchmarks/runStatistics/runExamples build every program in parallel (src/tools/parallelBuild.nim, osproc.execProcesses, one per core, each build's output in its own .log) and run them one at a time. Builds use -d:release (checks and asserts stay on): Geist's suite went from 11:24 to 2:09. Falls back to one-by-one builds when the helper cannot be built.
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
