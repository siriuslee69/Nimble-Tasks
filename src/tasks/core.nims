## ---------------------------------------------------------------------------
## core <- the parts every shared task stands on
## ---------------------------------------------------------------------------
##
##   sharedTaskNames  the ONE list of task names this repo provides
##   sharedTask       `task`, but skipped when the repo claims the name
##   hint             the line printed before any task runs
##   entryOf          finds a frontend's entry file, or stops with an error
##
## How a repo claims a name (its own `test`, for example):
##
##     const
##       ownTasks: array[1, string] = ["test"]
##     include "submodules/Nimble-Tasks/src/nimbleTasks.nims"
##
##     task test, "Run the repo's own test list":
##       ...
##
## Without the claim, both `task test` blocks exist and Nim stops with
## "redefinition of 'testTask'".

import std/[os, strutils]

const
  sharedTaskNames: array[28, string] = [
    # git
    "autopush", "switch", "applyNightly", "mainToNightlySnap",
    # submodules
    "find", "updateSubmodules", "submoduleStatus",
    # frontends
    "runWebui", "buildWebui", "runCli", "buildCli", "runTui", "buildTui",
    "runOwl", "buildOwl", "runServer", "buildServer",
    "buildAndroid", "installAndroid", "buildAll",
    # evaluation
    "test", "runTests", "runBenchmarks", "runStatistics", "runExamples",
    "evaluate",
    # housekeeping
    "clean", "sharedTasks"
  ]
  builtinCommands: array[12, string] = [
    "build", "install", "uninstall", "c", "cc", "js", "run", "check",
    "dump", "tasks", "develop", "refresh"
  ]
  nimbleTasksDir: string = parentDir(parentDir(parentDir(currentSourcePath())))

proc normalizedNames(): seq[string] =
  ## sharedTaskNames the way nimble compares them: lowercase, no "_".
  var
    T: seq[string] = @[]
  for t in sharedTaskNames:
    T.add(normalize(t))
  result = T

const
  sharedTaskKeys: seq[string] = normalizedNames()

proc displayName(c: string): string =
  ## c: normalized name; returns its spelling in sharedTaskNames.
  result = c
  for t in sharedTaskNames:
    if normalize(t) == c:
      result = t

proc claimedTasks(): seq[string] =
  ## Reads the repo's optional `ownTasks` list, spelled any way.
  var
    T: seq[string] = @[]
  when declared(ownTasks):
    for t in ownTasks:
      T.add(normalize(t))
  result = T

const
  repoOwnTasks: seq[string] = claimedTasks()

proc calledTask(): string =
  ## The task name nimble was asked for, or "" when nimble only reads the
  ## package details. Nimble passes: ... <file>.nimble <out file> <task> ...
  var
    i: int = 1
    t: string = ""
  while i <= paramCount() and not paramStr(i).endsWith(".nimble"):
    i.inc
  if i + 2 <= paramCount():
    t = normalize(paramStr(i + 2))
  result = t

proc isSharedCall(c: string): bool =
  ## c: normalized task name
  result = c in sharedTaskKeys and c notin repoOwnTasks

proc hint() =
  var
    c: string = calledTask()
    place: string = relativePath(nimbleTasksDir, getCurrentDir())
  if place.startsWith("../../"):
    place = nimbleTasksDir
  if c.len == 0 or c in builtinCommands:
    return
  if isSharedCall(c):
    echo "🌿 (｡•̀ᴗ-)✧ Calling outsourced nimble task `" & displayName(c) &
      "` from Nimble-Tasks submodule (" & place & ")"
  else:
    echo "🍃 ʕ•ᴥ•ʔ Other multipurpose tasks are available through " &
      "Nimble-Tasks submodule - beware of name collisions (`nimble sharedTasks`)"

template overrideOf(sym: untyped): string =
  ## The repo's own value for `sym` when it declared one, else "".
  when declared(sym): sym else: ""

template sharedTask(name: untyped; description: string; body: untyped) =
  ## `task`, registered only when the repo did not claim the name.
  static:
    doAssert normalize(astToStr(name)) in sharedTaskKeys,
      astToStr(name) & " is missing from sharedTaskNames in core.nims"
  when normalize(astToStr(name)) notin repoOwnTasks:
    task name, description:
      body

proc stop(msg: string) =
  ## Every shared task fails the same way: one clear line, exit code 1.
  quit("🥀 (╥﹏╥) " & msg, 1)

proc gitRaw(args: string): tuple[output: string, exitCode: int] =
  ## args: one git subcommand line, run in the repo nimble was called in.
  ## gorgeEx alone would run it in THIS file's folder, i.e. in Nimble-Tasks.
  result = gorgeEx("git -C " & quoteShell(getCurrentDir()) & " " & args)

proc firstExisting(A: openArray[string]): string =
  ## A: candidate paths, best first. Returns "" when none exists.
  var
    t: string = ""
  for a in A:
    if t.len == 0 and fileExists(a):
      t = a
  result = t

proc firstExistingDir(A: openArray[string]): string =
  ## A: candidate folders, best first. Returns "" when none exists.
  var
    t: string = ""
  for a in A:
    if t.len == 0 and dirExists(a):
      t = a
  result = t

proc packageTag(): string =
  ## The .nimble file's name without extension, e.g. "tyr" for tyr.nimble.
  var
    t: string = ""
  for f in listFiles(getCurrentDir()):
    if t.len == 0 and f.endsWith(".nimble"):
      t = splitFile(f).name
  result = t

proc exeName(s: string): string =
  ## s: bare program name; adds ".exe" on Windows.
  result = s
  when defined(windows):
    result.add(".exe")
