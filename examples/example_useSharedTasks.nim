## ---------------------------------------------------------------------------
## example_useSharedTasks <- the shortest repo that uses Nimble-Tasks
## ---------------------------------------------------------------------------
##
## What it does: writes a tiny repo into build/example_demo/, with ONE
## .nimble file, then calls two shared tasks on it as a person would.
##
##   build/example_demo/
##     demo.nimble                   <- the include block: the whole API
##     src/clients/cli/app_cli.nim   <- what `nimble runCli` starts
##
## A real repo writes the include block like this (folders side by side):
##
##     when fileExists(thisDir() & "/../Nimble-Tasks/src/nimbleTasks.nims"):
##       include "../Nimble-Tasks/src/nimbleTasks.nims"
##     elif fileExists(thisDir() & "/submodules/Nimble-Tasks/src/nimbleTasks.nims"):
##       include "submodules/Nimble-Tasks/src/nimbleTasks.nims"
##     else:
##       {.error: "Nimble-Tasks not found: git submodule update --init".}
##
## Settings go on `const` lines BEFORE that block (see the README table):
##
##     const
##       owlEntry: string = "src/gui/main.nim"   <- a window in an odd place
##       nixShell: string = "nix/gtk.nix"        <- GTK libraries on NixOS
##
## Run it:  nimble runExamples

import std/[os, osproc, strutils]
import runePragmas

const
  repoRoot: string = currentSourcePath().parentDir.parentDir
  tasksFile: string = repoRoot / "src" / "nimbleTasks.nims"
  demoDir: string = repoRoot / "build" / "example_demo"
  demoNimble: string = "version = \"0.1.0\"\nauthor = \"demo\"\n" &
    "description = \"a repo that borrows every chore\"\nlicense = \"MIT\"\n"
  demoProgram: string = "echo \"hello from the demo\"\n"

proc writeDemo(dir: string) {.role: dataWriter.} =
  ## dir: the folder the demo repo is written into; made when missing.
  createDir(dir / "src" / "clients" / "cli")
  writeFile(dir / "demo.nimble",
    demoNimble & "include \"" & tasksFile.replace('\\', '/') & "\"\n")
  writeFile(dir / "src" / "clients" / "cli" / "app_cli.nim", demoProgram)

proc callNimble(dir, args: string): tuple[output: string, exitCode: int] {.role: helper.} =
  ## dir: folder the call runs in; args: what follows `nimble`.
  result = execCmdEx("nimble --silent " & args & " 2>&1", workingDir = dir)

proc main(): int {.role: orchestrator.} =
  ## Returns 0 when both shared tasks did what the README says, else 1.
  var
    run: tuple[output: string, exitCode: int] = ("", -1)
    list: tuple[output: string, exitCode: int] = ("", -1)
  result = 0
  writeDemo(demoDir)
  run = callNimble(demoDir, "runCli")
  list = callNimble(demoDir, "sharedTasks")
  echo "nimble runCli      -> ", run.output.strip().splitLines()[^1]
  echo "nimble sharedTasks -> ", list.output.countLines(), " lines, runOwl listed: ",
    "runOwl" in list.output
  if run.exitCode != 0 or "hello from the demo" notin run.output:
    result = 1
  if list.exitCode != 0 or "runOwl" notin list.output:
    result = 1

quit(main())
