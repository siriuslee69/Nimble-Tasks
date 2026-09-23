## ---------------------------------------------------------------------------
## test_shared_tasks <- builds throwaway repos and drives them with nimble
## ---------------------------------------------------------------------------
##
##   <temp>/nimble_tasks_fixture/
##     app/        a repo that includes src/nimbleTasks.nims
##     upstream/   a plain git repo used as app's submodule
##     lost/       a repo whose include path leads nowhere
##
## Every check runs the real `nimble` program, so what passes here is what
## a person typing `nimble runCli` sees.

import std/[os, osproc, strutils, unittest]
import runePragmas

const
  sharedFile: string = currentSourcePath().parentDir.parentDir.parentDir /
    "src" / "nimbleTasks.nims"

var
  root: string = getTempDir() / "nimble_tasks_fixture"

proc sh(dir, cmd: string): tuple[output: string, exitCode: int] {.role: helper.} =
  ## dir: folder the command runs in; cmd: shell command line
  result = execCmdEx(cmd, workingDir = dir)

proc mustSh(dir, cmd: string) {.role: helper.} =
  var
    t: tuple[output: string, exitCode: int] = sh(dir, cmd)
  if t.exitCode != 0:
    raise newException(OSError, cmd & " failed:\n" & t.output)

proc nimbleFile(extra, own: string): string {.role: helper.} =
  ## extra: consts written before the include; own: tasks written after it
  result = "version = \"0.1.0\"\nauthor = \"x\"\ndescription = \"x\"\n" &
    "license = \"MIT\"\n" & extra & "include \"" & sharedFile & "\"\n" & own

proc initRepo(dir: string) {.role: helper.} =
  createDir(dir)
  mustSh(dir, "git init -q -b main")
  mustSh(dir, "git config user.email t@t && git config user.name t")

proc buildFixture() {.role: helper.} =
  removeDir(root)
  initRepo(root / "app")
  writeFile(root / "app" / "app.nimble", nimbleFile(
    "const\n  ownTasks: array[1, string] = [\"runTests\"]\n" &
    "  tuiEntry: string = \"elsewhere/tui.nim\"\n",
    "task hello, \"own task\":\n  echo \"hello from the repo\"\n" &
    "task runTests, \"own tests\":\n  echo \"own runTests ran\"\n"))
  createDir(root / "app" / "src" / "clients" / "cli")
  writeFile(root / "app" / "src" / "clients" / "cli" / "app_cli.nim",
    "echo \"cli is alive\"\n")
  createDir(root / "app" / "elsewhere")
  writeFile(root / "app" / "elsewhere" / "tui.nim", "echo \"tui from elsewhere\"\n")
  createDir(root / "app" / "evaluation" / "tests" / "deep")
  writeFile(root / "app" / "evaluation" / "tests" / "deep" / "test_one.nim",
    "echo \"test_one passed\"\n")
  writeFile(root / "app" / "evaluation" / "tests" / "helper.nim", "quit 7\n")
  mustSh(root / "app", "git add -A && git commit -qm init")
  initRepo(root / "upstream")
  writeFile(root / "upstream" / "a.txt", "1")
  mustSh(root / "upstream", "git add -A && git commit -qm one")
  mustSh(root / "app", "git submodule add -q ../upstream submodules/upstream")
  mustSh(root / "app", "git commit -qm 'add submodule'")
  writeFile(root / "upstream" / "a.txt", "2")
  mustSh(root / "upstream", "git commit -qam two")
  createDir(root / "lost")
  writeFile(root / "lost" / "lost.nimble",
    "version = \"0.1.0\"\nauthor = \"x\"\ndescription = \"x\"\nlicense = \"MIT\"\n" &
    "when fileExists(thisDir() & \"/../Nimble-Tasks/src/nimbleTasks.nims\"):\n" &
    "  include \"../Nimble-Tasks/src/nimbleTasks.nims\"\n" &
    "else:\n  {.error: \"Nimble-Tasks not found\".}\n")

proc nimble(dir, args: string): tuple[output: string, exitCode: int] {.role: helper.} =
  result = sh(root / dir, "nimble --silent " & args & " 2>&1")

# local file submodules are refused by git unless this is allowed
putEnv("GIT_CONFIG_COUNT", "1")
putEnv("GIT_CONFIG_KEY_0", "protocol.file.allow")
putEnv("GIT_CONFIG_VALUE_0", "always")
buildFixture()

suite "shared nimble tasks":
  # {.testKind: tkIntegration.}
  test "a shared task prints the outsourced hint and runs":
    var
      t: tuple[output: string, exitCode: int] = nimble("app", "runCli")
    check t.exitCode == 0
    check "Calling outsourced nimble task `runCli` from Nimble-Tasks" in t.output
    check "cli is alive" in t.output

  # {.testKind: tkIntegration.}
  test "a repo's own task prints the collision hint":
    var
      t: tuple[output: string, exitCode: int] = nimble("app", "hello")
    check "Other multipurpose tasks are available through Nimble-Tasks" in t.output
    check "hello from the repo" in t.output

  # {.testKind: tkIntegration.}
  test "a claimed name runs the repo's version, not the shared one":
    var
      t: tuple[output: string, exitCode: int] = nimble("app", "runTests")
    check "own runTests ran" in t.output
    check "Other multipurpose tasks" in t.output

  # {.testKind: tkIntegration.}
  test "an entry override is honoured":
    var
      t: tuple[output: string, exitCode: int] = nimble("app", "runTui")
    check t.exitCode == 0
    check "tui from elsewhere" in t.output

  # {.testKind: tkEdgeCase.}
  test "a missing entry file stops with every place it looked":
    var
      t: tuple[output: string, exitCode: int] = nimble("app", "runWebui")
    check t.exitCode != 0
    check "No webui entry file found" in t.output
    check "src/clients/webui/app.nim" in t.output

  # {.testKind: tkIntegration.}
  test "build puts the program in build/":
    var
      t: tuple[output: string, exitCode: int] = nimble("app", "buildCli")
    check t.exitCode == 0
    check fileExists(root / "app" / "build" / addFileExt("app_cli", ExeExt))

  # {.testKind: tkIntegration.}
  test "test runs test*.nim in subfolders and skips helpers":
    var
      t: tuple[output: string, exitCode: int] = nimble("app", "test")
    check t.exitCode == 0
    check "test_one passed" in t.output

  # {.testKind: tkIntegration.}
  test "updateSubmodules pins to upstream's newest main and commits":
    var
      t: tuple[output: string, exitCode: int] = nimble("app", "updateSubmodules")
    check t.exitCode == 0
    check readFile(root / "app" / "submodules" / "upstream" / "a.txt") == "2"
    check "Pin submodules to newest main" in sh(root / "app", "git log -1 --format=%s").output

  # {.testKind: tkEdgeCase.}
  test "updateSubmodules on a pinned-up-to-date repo commits nothing":
    var
      t: tuple[output: string, exitCode: int] = nimble("app", "updateSubmodules")
    check t.exitCode == 0
    check "already sit on their newest commit" in t.output

  # {.testKind: tkEdgeCase.}
  test "a repo that cannot find Nimble-Tasks fails loudly":
    var
      t: tuple[output: string, exitCode: int] = nimble("lost", "tasks")
    check t.exitCode != 0
    check "Nimble-Tasks not found" in t.output

  # {.testKind: tkSmoke.}
  test "sharedTasks marks the names the repo replaced":
    var
      t: tuple[output: string, exitCode: int] = nimble("app", "sharedTasks")
    check "runTests   <- replaced by this repo" in t.output
    check "updateSubmodules" in t.output
