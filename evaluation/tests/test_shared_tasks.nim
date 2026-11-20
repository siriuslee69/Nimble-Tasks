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
  presetFile: string = currentSourcePath().parentDir.parentDir.parentDir /
    "src" / "preset.nims"
  presetProbe: string = "const\n  flavour {.strdefine.}: string = \"none\"\n" &
    "  level {.intdefine.}: int = -1\n" &
    "echo \"flavour=\", flavour, \" level=\", level, \" size=\", " &
    "compileOption(\"opt\", \"size\")\n"
    ## The program the preset repo builds: it prints what reached nim.

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

proc buildPresetFixture() {.role: helper.} =
  ## presets/ -- a repo whose config.nims includes preset.nims:
  ##   configs/default.toml  flavour = "plain", level = 1
  ##   configs/tiny.toml     flavour = "tiny", opt = "size", passC list
  var
    dir: string = root / "presets"
  initRepo(dir)
  writeFile(dir / "presets.nimble", nimbleFile("", ""))
  writeFile(dir / "config.nims", "include \"" & presetFile & "\"\napplyPreset()\n")
  createDir(dir / "configs")
  writeFile(dir / "configs" / "default.toml",
    "[define]\nflavour = \"plain\"  # comment\nlevel = 1\n[passC]\nflags = []\n")
  writeFile(dir / "configs" / "tiny.toml",
    "[nim]\nopt = \"size\"\n[define]\nflavour = \"tiny\"\n" &
    "[passC]\nflags = [\"-DA=1\",\n         \"-DB=2\"]\n[runtime]\nignored = 5\n")
  createDir(dir / "src" / "clients" / "cli")
  writeFile(dir / "src" / "clients" / "cli" / "app_cli.nim", presetProbe)
  mustSh(dir, "git add -A && git commit -qm init")

proc nimble(dir, args: string): tuple[output: string, exitCode: int] {.role: helper.} =
  result = sh(root / dir, "nimble --silent " & args & " 2>&1")

# local file submodules are refused by git unless this is allowed
putEnv("GIT_CONFIG_COUNT", "1")
putEnv("GIT_CONFIG_KEY_0", "protocol.file.allow")
putEnv("GIT_CONFIG_VALUE_0", "always")
buildFixture()
buildPresetFixture()

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

suite "compiler command override":
  # {.testKind: tkIntegration, covers: "nimCompiler".}
  test "compiler wrapper receives frontend and evaluation arguments":
    var
      dir: string = root / "compiler"
      wrapped: string = ""
      build: tuple[output: string, exitCode: int] = ("", -1)
      tests: tuple[output: string, exitCode: int] = ("", -1)
    initRepo(dir)
    writeFile(dir / "compiler.nimble", nimbleFile(
      "const nimCommand = \"sh compiler.sh\"\n", ""))
    writeFile(dir / "compiler.sh", "#!/bin/sh\nprintf '%s\\n' \"$*\" >> compiler.log\nexec nim \"$@\"\n")
    createDir(dir / "src" / "clients" / "cli")
    writeFile(dir / "src" / "clients" / "cli" / "app_cli.nim", "echo \"wrapped frontend\"\n")
    createDir(dir / "evaluation" / "tests")
    writeFile(dir / "evaluation" / "tests" / "test_wrapper.nim", "echo \"wrapped test\"\n")
    build = nimble("compiler", "buildCli")
    tests = nimble("compiler", "test")
    check build.exitCode == 0
    check tests.exitCode == 0
    check "wrapped test" in tests.output
    wrapped = readFile(dir / "compiler.log")
    check "src/clients/cli/app_cli.nim" in wrapped
    check "evaluation/tests/test_wrapper.nim" in wrapped

suite "build presets (preset.nims)":
  # {.testKind: tkIntegration, covers: "applyPreset".}
  test "configs/default.toml applies to a build that names no preset":
    var
      t: tuple[output: string, exitCode: int] = nimble("presets", "runCli")
    check t.exitCode == 0
    check t.output.contains("flavour=plain level=1 size=false")

  # {.testKind: tkIntegration, covers: "presetFlag".}
  test "nimble hands -d:preset on, and the preset lies over the base":
    var
      t: tuple[output: string, exitCode: int] = nimble("presets",
        "runCli -d:preset=tiny")
    check t.exitCode == 0
    check t.output.contains("flavour=tiny level=1 size=true")

  # {.testKind: tkIntegration, covers: "applyPreset".}
  test "the command line wins over every preset file":
    var
      t: tuple[output: string, exitCode: int] = sh(root / "presets",
        "nim c -r --hints:off -d:preset=tiny -d:flavour=cmd -o:build/p " &
        "src/clients/cli/app_cli.nim 2>&1")
    check t.exitCode == 0
    check t.output.contains("flavour=cmd level=1 size=true")

  # {.testKind: tkEdgeCase, covers: "applyPreset".}
  test "a preset that does not exist stops the build and names the file":
    var
      t: tuple[output: string, exitCode: int] = sh(root / "presets",
        "nim c --hints:off -d:preset=nope -o:build/p " &
        "src/clients/cli/app_cli.nim 2>&1")
    check t.exitCode != 0
    check t.output.contains("configs/nope.toml")

proc buildGtkFixture(): string {.role: helper.} =
  ## gtk/ -- a repo with an owl window and a nix shell file, plus fake/bin with
  ## a `pkg-config` that cannot see GTK4 and a `nix-shell` that logs its call,
  ## sets IN_NIX_SHELL and runs the --run text. Returns the fake/bin folder.
  var
    dir: string = root / "gtk"
    bin: string = dir / "fake" / "bin"
  initRepo(dir)
  writeFile(dir / "gtk.nimble", nimbleFile("", ""))
  createDir(dir / "src" / "clients" / "owl")
  writeFile(dir / "src" / "clients" / "owl" / "app.nim", "echo \"owl is alive\"\n")
  createDir(dir / "nix")
  writeFile(dir / "nix" / "shell.nix", "{}\n")
  createDir(bin)
  writeFile(bin / "pkg-config", "#!/bin/sh\nexit 1\n")
  writeFile(bin / "nix-shell",
    "#!/bin/sh\nfile=$1; shift; shift\nprintf '%s | %s\\n' \"$file\" \"$1\" >> " &
    (dir / "shell.log") & "\nIN_NIX_SHELL=impure exec sh -c \"$1\"\n")
  mustSh(dir, "chmod +x fake/bin/pkg-config fake/bin/nix-shell")
  result = bin

proc gtkRun(bin, env, args: string): tuple[output: string, exitCode: int] {.role: helper.} =
  ## bin: the fake folder put first on PATH; env: extra `NAME=value` words;
  ## args: what follows `nimble`.
  result = sh(root / "gtk", env & " PATH=" & bin & ":$PATH nimble --silent " & args & " 2>&1")

suite "GTK shell hop":
  var
    bin: string = buildGtkFixture()

  # {.testKind: tkIntegration, covers: "enterGtkShell".}
  test "runOwl runs again inside the nix shell when GTK4 is not visible":
    var
      t: tuple[output: string, exitCode: int] = gtkRun(bin, "", "runOwl -d:mark=1")
    check t.exitCode == 0
    check "running inside nix/shell.nix" in t.output
    check "owl is alive" in t.output
    check "nix/shell.nix | nimble runOwl -d:mark=1" in readFile(root / "gtk" / "shell.log")

  # {.testKind: tkEdgeCase, covers: "needsGtkShell".}
  test "already inside a nix shell, nothing hops again":
    var
      t: tuple[output: string, exitCode: int] = gtkRun(bin, "IN_NIX_SHELL=pure", "runOwl")
    check t.exitCode == 0
    check "running inside" notin t.output
    check "owl is alive" in t.output

  # {.testKind: tkEdgeCase, covers: "needsGtkShell".}
  test "a shell that can see GTK4 is left alone":
    var
      t: tuple[output: string, exitCode: int] = ("", -1)
    writeFile(bin / "pkg-config", "#!/bin/sh\nexit 0\n")
    t = gtkRun(bin, "", "runOwl")
    check t.exitCode == 0
    check "running inside" notin t.output
    check "owl is alive" in t.output

  # {.testKind: tkEdgeCase, covers: "needsGtkShell".}
  test "a repo with no window never hops":
    var
      t: tuple[output: string, exitCode: int] = nimble("app", "runCli")
    check t.exitCode == 0
    check "running inside" notin t.output
