# Nimble-Tasks

## Installation

### NixOS

```sh
cd MyRepo
git submodule add https://github.com/siriuslee69/Nimble-Tasks.git submodules/Nimble-Tasks
```

### Windows 11

```powershell
cd MyRepo
git submodule add https://github.com/siriuslee69/Nimble-Tasks.git submodules/Nimble-Tasks
```

Then add these lines to the end of the repo's `.nimble` file (same on both):

```nim
when fileExists(thisDir() & "/../Nimble-Tasks/src/nimbleTasks.nims"):
  include "../Nimble-Tasks/src/nimbleTasks.nims"
elif fileExists(thisDir() & "/submodules/Nimble-Tasks/src/nimbleTasks.nims"):
  include "submodules/Nimble-Tasks/src/nimbleTasks.nims"
else:
  {.error: "Nimble-Tasks not found: git submodule update --init submodules/Nimble-Tasks".}
```

### Quick check

```sh
nimble sharedTasks     # lists every shared task
nimble runCli          # runs the repo's command-line frontend
```

```
🌿 (｡•̀ᴗ-)✧ Calling outsourced nimble task `runCli` from Nimble-Tasks submodule (../Nimble-Tasks)
```

### What stays default, what you may change

```
┌──────────────────────────┬──────────────────────────────────────────┐
│ leave alone               │ free to set in your .nimble, BEFORE the │
│                           │ include                                 │
├──────────────────────────┼──────────────────────────────────────────┤
│ the include block above   │ ownTasks          names you replace     │
│ src/ of this repo         │ webuiEntry, cliEntry, tuiEntry,         │
│                           │ owlEntry, serverEntry, androidDir       │
│                           │ nimFlags, webuiFlags, cliFlags, …       │
│                           │ frozenSubmodules  never auto-updated    │
│                           │ extraArtifacts    autopush refuses them │
└──────────────────────────┴──────────────────────────────────────────┘
```

There is no config file. Everything is a `const` in the repo's own `.nimble`.

---

## ╭⟢ What this is 🌊

Every repo in the workspace needs the same chores: push, switch branch,
update submodules, start the web interface, run the tests. Each repo used
to carry its own copy of those chores, and the copies drifted apart:

```
runUi   runPanel   runDesktop   runWebUi   runWebui   webui   ui
   └────────┴──────────┴───────────┴──────────┴────────┴─────┘
                all meaning "start the program's window"
```

This repo holds **one** copy. A repo includes it, and gets every chore
under **one** name. Change a chore here, and every repo beside this one
has the change the next time it calls `nimble`.

```
      Nimble-Tasks/src/nimbleTasks.nims          (one file, one copy)
         │          │            │
     include     include      include
         │          │            │
     Tyr-Crypto  Bifrost-…   SIMD-Nexus   …   ← each keeps only its own tasks
```

## ├⟢ Words used below 🐦‍🔥

**Def. 1 — task.** A named job in a `.nimble` file, started with
`nimble <name>`. Example: `nimble runCli`.

**Def. 2 — shared task.** A task that lives in this repo, not in the repo
calling it. The full list is in Def. 6.

**Def. 3 — include.** Nim copies the text of another file into this spot,
as if it had been typed here. That is how a `.nimble` file gets the shared
tasks without copying them.

**Def. 4 — entry file.** The `.nim` file a frontend starts from, e.g.
`src/clients/cli/app_cli.nim` for the command line.

**Def. 5 — claiming a name.** A repo lists a shared task's name in
`ownTasks`. The shared version is then left out and the repo's own runs.

```nim
const
  ownTasks: array[1, string] = ["test"]
include "submodules/Nimble-Tasks/src/nimbleTasks.nims"

task test, "Run this repo's hand-picked test list":
  exec "nim c -r evaluation/tests/test_core.nim"
```

Without the claim, Nim stops with `redefinition of 'testTask'` — two tasks
cannot share a name. ʕ•ᴥ•ʔ

**Def. 6 — the shared tasks.**

```
group        task                what it does
───────────  ──────────────────  ──────────────────────────────────────────
git          autopush            stage all, refuse build output, commit with
                                 the "Commit Message:" line of
                                 agents/PROGRESS.md, push
             switch              nightly <-> main
             applyNightly        main moves forward to nightly
             mainToNightlySnap   nightly gets main's files, keeps its history
submodules   updateSubmodules    every submodule -> newest main commit, one
                                 commit "Pin submodules to newest main"
             submoduleStatus     which commit each submodule sits on
             find                point submodules at sibling folders
frontends    runWebui buildWebui    nim-webui window
             runCli   buildCli      command line
             runTui   buildTui      terminal (illwill)
             runOwl   buildOwl      GTK4 (owlkettle)
             runServer buildServer  server
             buildAndroid           Android debug .apk (Gradle)
             installAndroid         .apk onto a connected phone
             buildAll               every frontend the repo has
evaluation   test = runTests     evaluation/tests/**/test*.nim
             runBenchmarks       evaluation/benchmarks/**/bench*.nim
             runStatistics       evaluation/statistics/**/stat*.nim
             runExamples         examples/**/*.nim
             evaluate            Otter's whole-repo check, now
other        clean               delete build/ and nimcache/
             sharedTasks         print this list
```

## ├⟢ How a call travels 🍣

```
nimble runCli
   │
   ▼
repo.nimble ── include ──► nimbleTasks.nims
                               │
                               ├─ core.nims       which task was called?
                               │                   print the hint line
                               ├─ git.nims         ┐
                               ├─ submodules.nims  │ each `sharedTask` is
                               ├─ android.nims     │ skipped if the repo
                               ├─ frontends.nims   │ claimed its name
                               └─ evaluation.nims  ┘
                                        │
                                        ▼
                  runCli: find entry file ── none? ──► stop, list the
                          │                             places looked in
                          ▼
                  nim c -r src/clients/cli/app_cli.nim
```

**The hint line.** Printed once, before the task starts:

```
called task is …                 printed
───────────────────────────────  ─────────────────────────────────────────
a shared task                    🌿 (｡•̀ᴗ-)✧ Calling outsourced nimble task
                                    `runCli` from Nimble-Tasks submodule (…)
the repo's own task              🍃 ʕ•ᴥ•ʔ Other multipurpose tasks are
                                    available through Nimble-Tasks submodule
                                    - beware of name collisions
nimble build / install / tasks   nothing
```

**Where entry files are looked for.** First one that exists wins:

```
frontend  looked for, in this order
────────  ───────────────────────────────────────────
webui     src/clients/webui/app.nim
          src/client/frontend/webui/app.nim
          src/client/webui/app.nim
          src/client/frontend/webui_ui/app.nim
          src/clients/web/app.nim
cli       src/clients/cli/app_cli.nim
          src/clients/cli/main.nim
          src/client/frontend/cli/app_cli.nim
tui       src/clients/tui/app_tui.nim
          src/client/frontend/tui/app_tui.nim
          src/client/frontend/illwill_tui/app_tui.nim
owl       src/clients/owl/app.nim
          src/clients/gtk/app.nim
          src/client/frontend/owlkettle_ui/app.nim
          src/client/frontend/desktop/app.nim
server    src/server/server.nim
          src/server/main.nim
          src/server/app.nim
android   android/   src/clients/android/   src/client/frontend/android/
```

Each place is also tried inside `src/<package>/`, e.g.
`src/proto/client/frontend/cli/app_cli.nim` for a package called `proto`.

`run…` makes a debug program and starts it. `build…` makes a release
program at `build/<package>_<frontend>`, e.g. `build/tyr_cli`.

**How updateSubmodules picks a commit.**

```
.gitmodules says branch = X ?  ── yes ──► origin/X
          │ no
origin has main ?              ── yes ──► origin/main
          │ no
origin has master ?            ── yes ──► origin/master
          │ no
                                          origin's default branch
```

A submodule with uncommitted work stops the task — nothing is thrown away.
Nothing is pushed; the pins are one local commit.

## ╰⟢ Files 🌱

```
Nimble-Tasks/
├── nimble_tasks.nimble          includes the shared file on itself
├── src/
│   ├── nimbleTasks.nims         the one file repos include
│   ├── preset.nims              build presets (configs/*.toml), included
│   │                            by a repo's config.nims, not its .nimble
│   └── tasks/
│       ├── core.nims            names list, hint, sharedTask, lookups
│       ├── git.nims
│       ├── submodules.nims
│       ├── android.nims
│       ├── frontends.nims
│       └── evaluation.nims
├── evaluation/tests/
│   └── test_shared_tasks.nim    builds throwaway repos, drives real nimble
└── agents/PROGRESS.md
```

Adding a task: write it with `sharedTask` in the fitting file, and add its
name to `sharedTaskNames` in `core.nims`. Forgetting the second step stops
the build with `<name> is missing from sharedTaskNames`. (ᵔᴥᵔ)

Testing: `nimble test`.

---

## ╰⟢ Build presets (preset.nims) 🌾

One `.toml` file per kind of build instead of a long flag list. A repo keeps
them in `configs/`; `default.toml` lists every switch the repo has, at its
default value, and applies to every build.

```text
nim c app.nim                     configs/default.toml
nim c -d:preset=iot app.nim       default.toml, then configs/iot.toml over it
nimble buildCli -d:preset=iot     the same: shared tasks pass it on to nim
nim c -d:preset=iot -d:x=1 ...    the command line wins over both files
```

```toml
[nim]                         # --opt:size ...
opt = "size"
[define]                      # -d:bifrostKems=saber,x25519 ; true -> -d:name
bifrostKems = "saber,x25519"  # "" or false -> not set (the built-in default)
[passC]
flags = ["-flto"]
[runtime]                     # not a flag: the program and nix/module.nix read it
```

Wire it in with four lines at the end of `config.nims`:

```nim
when fileExists(thisDir() & "/../Nimble-Tasks/src/preset.nims"):
  include "../Nimble-Tasks/src/preset.nims"
elif fileExists(thisDir() & "/submodules/Nimble-Tasks/src/preset.nims"):
  include "submodules/Nimble-Tasks/src/preset.nims"
applyPreset()
```

The files applied reach the program as `-d:presetFiles=a.toml;b.toml`, so
its own code can read other sections while compiling. Why `-d:preset=`
and not `--preset:`: nim refuses any `--option` it does not know before
`config.nims` runs, while a `-d:` define may carry any name.

---

## ⚠ Issue playbook

```
symptom                                  cause / workaround
───────────────────────────────────────  ─────────────────────────────────────
redefinition of 'testTask'               repo defines a shared name. Add it to
                                         `ownTasks`, or delete the repo's copy.
Nimble-Tasks not found                   neither ../Nimble-Tasks nor the
                                         submodule exists:
                                         git submodule update --init
my `const webuiEntry` is ignored         it must come BEFORE the include
evaluate fails on Windows                otter-gate is a shell script; run it
                                         from Git Bash or WSL
a git command acts on the wrong repo     only ever call git through
                                         `captureGit`/`gitRaw`: plain gorgeEx
                                         runs in Nimble-Tasks' own folder
```

---

## Conventions in brief

```
style       Nim, `var` blocks with starting values, no `let`
nesting     no loop in a loop, no if in an if - pull it into a proc
names       one-letter parameters (A for lists, S for state), doc line below
placeholder any unfinished routine starts with ph_
layout      agents/PROGRESS.md, src/, evaluation/{tests,benchmarks,statistics}
pragmas     role/tag/testKind come from the shared Rune-Pragmas repo
branches    work on nightly, `nimble applyNightly` moves main forward
```
