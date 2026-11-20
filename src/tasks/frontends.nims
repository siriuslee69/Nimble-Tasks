## ---------------------------------------------------------------------------
## frontends <- one name per way of running the program, in every repo
## ---------------------------------------------------------------------------
##
##   frontend   run task     build task    entry file looked for (first wins)
##   ---------  -----------  ------------  -----------------------------------
##   webui      runWebui     buildWebui    src/clients/webui/app.nim
##                                         src/client/frontend/webui/app.nim
##                                         src/client/webui/app.nim
##                                         src/client/frontend/webui_ui/app.nim
##                                         src/clients/web/app.nim
##   cli        runCli       buildCli      src/clients/cli/app_cli.nim
##                                         src/clients/cli/main.nim
##                                         src/client/frontend/cli/app_cli.nim
##   tui        runTui       buildTui      src/clients/tui/app_tui.nim
##                                         src/client/frontend/tui/app_tui.nim
##                                         src/client/frontend/illwill_tui/app_tui.nim
##   owl        runOwl       buildOwl      src/clients/owl/app.nim
##                                         src/clients/gtk/app.nim
##                                         src/client/frontend/owlkettle_ui/app.nim
##                                         src/client/frontend/desktop/app.nim
##   server     runServer    buildServer   src/server/server.nim
##                                         src/server/main.nim
##                                         src/server/app.nim
##
## Each place is also tried inside src/<package>/ (src/proto/client/… for a
## package called proto), which is where nimble's package layout puts it.
##
## A repo whose file sits elsewhere says so before the include:
##
##     const
##       owlEntry: string = "src/clients/desktop/shell.nim"
##
## Extra compiler flags, all optional, all added in this order:
##
##     nimFlags        every frontend        e.g. "--threads:on"
##     webuiFlags      only webui            e.g. "-d:useStdLib"
##     cliFlags, tuiFlags, owlFlags, serverFlags
##
## run*   -> nim c -r, debug build, cache in build/nimcache_<frontend>
## build* -> nim c -d:release, program in build/<package>_<frontend>
## Neither finds a file? It stops and lists every place it looked.
##
## GTK without typing `nix-shell`: runOwl, buildOwl, buildAll and the
## evaluation tasks call `enterGtkShell()` first. When ALL of these hold, the
## same nimble call is run again inside the repo's nix shell, once:
##
##   the repo has an owl entry          and a shell file (`nixShell` const,
##                                      else nix/owlkettle-shell.nix, else
##                                      nix/shell.nix)
##   not Windows, IN_NIX_SHELL unset    nix-shell exists
##   the repo sets no `nimCommand`      `pkg-config --exists gtk4` fails here
##
## Any "no" and the task runs where it stands, as before.

proc candidatesOf(kind: string): seq[string] =
  ## kind: webui | cli | tui | owl | server
  case kind
  of "webui":
    result = @["src/clients/webui/app.nim", "src/client/frontend/webui/app.nim",
      "src/client/webui/app.nim", "src/client/frontend/webui_ui/app.nim",
      "src/clients/web/app.nim"]
  of "cli":
    result = @["src/clients/cli/app_cli.nim", "src/clients/cli/main.nim",
      "src/client/frontend/cli/app_cli.nim"]
  of "tui":
    result = @["src/clients/tui/app_tui.nim", "src/client/frontend/tui/app_tui.nim",
      "src/client/frontend/illwill_tui/app_tui.nim"]
  of "owl":
    result = @["src/clients/owl/app.nim", "src/clients/gtk/app.nim",
      "src/client/frontend/owlkettle_ui/app.nim",
      "src/client/frontend/desktop/app.nim"]
  of "server":
    result = @["src/server/server.nim", "src/server/main.nim", "src/server/app.nim"]
  else:
    result = @[]

proc searchList(kind: string): seq[string] =
  ## Every usual place, then the same places inside src/<package>/, which is
  ## where nimble's package layout puts them (src/proto/client/… for proto).
  var
    B: seq[string] = candidatesOf(kind)
    T: seq[string] = candidatesOf(kind)
    pkg: string = packageTag()
  for b in B:
    T.add("src/" & pkg & b[len("src") .. ^1])
  result = T

proc overrideEntry(kind: string): string =
  ## The repo's `<kind>Entry` const, or "".
  case kind
  of "webui": result = overrideOf(webuiEntry)
  of "cli": result = overrideOf(cliEntry)
  of "tui": result = overrideOf(tuiEntry)
  of "owl": result = overrideOf(owlEntry)
  of "server": result = overrideOf(serverEntry)
  else: result = ""

proc overrideFlags(kind: string): string =
  ## The repo's `nimFlags` plus its `<kind>Flags`, space separated.
  var
    t: string = overrideOf(nimFlags)
  case kind
  of "webui": t = t & " " & overrideOf(webuiFlags)
  of "cli": t = t & " " & overrideOf(cliFlags)
  of "tui": t = t & " " & overrideOf(tuiFlags)
  of "owl": t = t & " " & overrideOf(owlFlags)
  of "server": t = t & " " & overrideOf(serverFlags)
  else: discard
  result = t.strip()

proc findEntry(kind: string): string =
  ## "" when neither the override nor any usual place holds the file.
  var
    t: string = overrideEntry(kind)
  if t.len > 0 and not fileExists(t):
    stop(kind & "Entry points at " & t & ", which does not exist.")
  if t.len == 0:
    t = firstExisting(searchList(kind))
  result = t

proc entryOf(kind: string): string =
  ## Like findEntry, but stops with the list of places it looked.
  var
    t: string = findEntry(kind)
  if t.len == 0:
    stop("No " & kind & " entry file found. Looked in:\n    " &
      searchList(kind).join("\n    ") &
      "\n  Put it in one of those, or set `const " & kind &
      "Entry: string = \"path/to/file.nim\"` before the include.")
  result = t

proc gtkShellFile(): string =
  ## The nix shell that holds this repo's GTK libraries: its own `nixShell`
  ## const, else nix/owlkettle-shell.nix, else nix/shell.nix. "" when none.
  var
    t: string = overrideOf(nixShell)
  if t.len == 0:
    t = firstExisting(["nix/owlkettle-shell.nix", "nix/shell.nix"])
  result = t

proc needsGtkShell(): bool =
  ## true only when ALL hold; any "no" leaves the task running where it is:
  ##   not Windows, not already inside a nix shell, the repo names no compiler
  ##   wrapper of its own, it has a GTK window (owl entry) and a shell file,
  ##   nix-shell exists, and pkg-config cannot see GTK4 from here.
  result = false
  when defined(windows):
    return
  if getEnv("IN_NIX_SHELL").len > 0 or overrideOf(nimCommand).len > 0:
    return
  if gtkShellFile().len == 0 or findEntry("owl").len == 0:
    return
  if gorgeEx("command -v nix-shell").exitCode != 0:
    return
  result = gorgeEx("pkg-config --exists gtk4").exitCode != 0

proc enterGtkShell(): bool =
  ## Runs this very nimble call again inside the repo's nix shell and returns
  ## true: the task is done and must `return` at once. Returns false, having
  ## done nothing, when `needsGtkShell` says no. (`quit` would make nimble
  ## report "Failed to execute task", so the caller returns instead.)
  ##
  ##   nimble runOwl -d:preset=iot
  ##     └─ GTK not visible ─▶ nix-shell nix/owlkettle-shell.nix --run 'nimble runOwl -d:preset=iot'
  ##                              └─ IN_NIX_SHELL is set, so the second call runs the task
  ##
  ## A task calls it first:   if enterGtkShell(): return
  var
    cmd: string = "nimble"
  result = false
  if not needsGtkShell():
    return
  for a in calledParams():
    cmd.add(" " & quoteShell(a))
  echo "🌿 GTK4 is not visible here; running inside " & gtkShellFile()
  exec "nix-shell " & quoteShell(gtkShellFile()) & " --run " & quoteShell(cmd)
  result = true

proc runFrontend(kind: string) =
  if kind == "owl" and enterGtkShell():
    return
  exec nimCompiler() & " c -r" & presetFlag() & " " & overrideFlags(kind) & " --nimcache:build/nimcache_" & kind &
    " -o:" & quoteShell(joinPath("build", exeName(packageTag() & "_" & kind & "_debug"))) &
    " " & quoteShell(entryOf(kind))

proc buildFrontend(kind: string) =
  if kind == "owl" and enterGtkShell():
    return
  mkDir("build")
  exec nimCompiler() & " c -d:release" & presetFlag() & " " & overrideFlags(kind) & " --nimcache:build/nimcache_" &
    kind & "_release -o:" &
    quoteShell(joinPath("build", exeName(packageTag() & "_" & kind))) &
    " " & quoteShell(entryOf(kind))
  echo "Built build/" & exeName(packageTag() & "_" & kind)

sharedTask runWebui, "Run the WebUI frontend":
  runFrontend("webui")

sharedTask buildWebui, "Build the WebUI frontend for release":
  buildFrontend("webui")

sharedTask runCli, "Run the command-line frontend":
  runFrontend("cli")

sharedTask buildCli, "Build the command-line frontend for release":
  buildFrontend("cli")

sharedTask runTui, "Run the terminal (illwill) frontend":
  runFrontend("tui")

sharedTask buildTui, "Build the terminal (illwill) frontend for release":
  buildFrontend("tui")

sharedTask runOwl, "Run the GTK4 (owlkettle) frontend":
  runFrontend("owl")

sharedTask buildOwl, "Build the GTK4 (owlkettle) frontend for release":
  buildFrontend("owl")

sharedTask runServer, "Run the server":
  runFrontend("server")

sharedTask buildServer, "Build the server for release":
  buildFrontend("server")

sharedTask buildAll, "Build every frontend this repo has, for release":
  var
    built: int = 0
  if enterGtkShell():
    return
  for kind in ["webui", "cli", "tui", "owl", "server"]:
    if findEntry(kind).len > 0:
      buildFrontend(kind)
      built.inc
  if androidDirOrEmpty().len > 0:
    buildAndroidApk()
    built.inc
  if built == 0:
    stop("No frontend found - nothing to build. `nimble runWebui` lists where it looks.")
