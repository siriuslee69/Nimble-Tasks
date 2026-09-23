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
    t = firstExisting(candidatesOf(kind))
  result = t

proc entryOf(kind: string): string =
  ## Like findEntry, but stops with the list of places it looked.
  var
    t: string = findEntry(kind)
  if t.len == 0:
    stop("No " & kind & " entry file found. Looked in:\n    " &
      candidatesOf(kind).join("\n    ") &
      "\n  Put it in one of those, or set `const " & kind &
      "Entry: string = \"path/to/file.nim\"` before the include.")
  result = t

proc runFrontend(kind: string) =
  exec "nim c -r " & overrideFlags(kind) & " --nimcache:build/nimcache_" & kind &
    " -o:" & quoteShell(joinPath("build", exeName(packageTag() & "_" & kind & "_debug"))) &
    " " & quoteShell(entryOf(kind))

proc buildFrontend(kind: string) =
  mkDir("build")
  exec "nim c -d:release " & overrideFlags(kind) & " --nimcache:build/nimcache_" &
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
  for kind in ["webui", "cli", "tui", "owl", "server"]:
    if findEntry(kind).len > 0:
      buildFrontend(kind)
      built.inc
  if androidDirOrEmpty().len > 0:
    buildAndroidApk()
    built.inc
  if built == 0:
    stop("No frontend found - nothing to build. `nimble runWebui` lists where it looks.")
