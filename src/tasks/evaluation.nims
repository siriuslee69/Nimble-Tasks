## ---------------------------------------------------------------------------
## evaluation <- tests, benchmarks, statistics, examples, the Otter check
## ---------------------------------------------------------------------------
##
##   task           folder                    files it runs (all subfolders)
##   -------------  ------------------------  -----------------------------
##   runTests       evaluation/tests/         test*.nim
##   runBenchmarks  evaluation/benchmarks/    bench*.nim
##   runStatistics  evaluation/statistics/    stat*.nim
##   runExamples    examples/                 *.nim
##   test           = runTests
##   evaluate       Otter's whole-repo check, right now (otter-gate --force)
##
## Only files starting with the prefix run, so helper modules living in the
## same folder (paths.nim, fixtures.nim, …) are left alone.
## Each program lands in build/evaluation/, never beside its source.
## A missing folder, or a folder with nothing to run, stops with an error.

proc programsIn(dir, prefix: string): seq[string] =
  ## dir: folder searched with all subfolders; prefix: "" takes every .nim
  var
    T: seq[string] = @[]
  if not dirExists(dir):
    stop(dir & " does not exist.")
  for p in walkDirRec(dir):
    if p.endsWith(".nim") and splitFile(p).name.startsWith(prefix):
      T.add(p)
  if T.len == 0:
    stop("Nothing to run in " & dir & " (looking for " & prefix & "*.nim).")
  result = T

proc programPath(p: string): string =
  ## p: a source file -> where its program is built (build/evaluation/<name>).
  result = joinPath("build", "evaluation", exeName(splitFile(p).name))

proc parallelHelper(): string =
  ## Builds tools/parallelBuild.nim once into build/ and returns its path, or
  ## "" when it cannot be built here (no Rune-Pragmas beside Nimble-Tasks):
  ## the caller then builds one file at a time, exactly as before.
  var
    src: string = joinPath(currentSourcePath().parentDir().parentDir(), "tools", "parallelBuild.nim")
    exe: string = joinPath(thisDir(), "build", exeName("nimbleTasksParallelBuild"))
    pragmas: string = firstExistingDir([
      joinPath(src.parentDir().parentDir().parentDir().parentDir(), "Rune-Pragmas", "meta"),
      joinPath(src.parentDir().parentDir().parentDir(), "submodules", "Rune-Pragmas", "meta"),
      joinPath(thisDir(), "..", "Rune-Pragmas", "meta"), joinPath(thisDir(), "submodules", "Rune-Pragmas", "meta")])
  # A copy of the source sits beside the program: same text, no rebuild.
  if fileExists(exe) and fileExists(exe & ".src") and readFile(exe & ".src") == readFile(src):
    return exe
  if pragmas.len == 0:
    return ""
  mkDir(joinPath(thisDir(), "build"))
  if gorgeEx("nim c --hints:off -d:release --path:" & quoteShell(pragmas) &
      " -o:" & quoteShell(exe) & " " & quoteShell(src)).exitCode == 0:
    writeFile(exe & ".src", readFile(src))
    result = exe

proc compileAndRun(A: seq[string]) =
  ## A: Nim programs; all are built first, side by side (one per CPU core),
  ## then run ONE AT A TIME in order. The first failure stops.
  ##
  ##   build   test_a  test_b  test_c ...   together   (where the time goes)
  ##   run     test_a, then test_b, ...     one by one (tests may share
  ##                                                    ports and temp folders)
  ##
  ## Built with -d:release: optimised, but bounds/overflow checks and asserts
  ## stay on (only -d:danger removes them). A debug build ran Argon2id 19x
  ## slower (2.2 s instead of 0.12 s), which made crypto-heavy suites take
  ## many minutes, and made benchmarks measure the debug build. Rebuild one
  ## test without -d:release by hand when a stack trace is needed.
  var
    helper: string = parallelHelper()
    flags: string = " -d:release" & presetFlag() & " " & overrideOf(nimFlags) & " --hints:off"
    jobs: string = ""
  mkDir(joinPath("build", "evaluation"))
  if helper.len == 0:
    for p in A:
      exec "nim c -r" & flags & " -o:" & quoteShell(programPath(p)) & " " & quoteShell(p)
    return
  for p in A:
    jobs.add programPath(p) & ".log\tnim c" & flags & " -o:" & quoteShell(programPath(p)) &
      " " & quoteShell(p) & "\n"
  writeFile(joinPath("build", "evaluation", "parallel.txt"), jobs)
  exec quoteShell(helper) & " " & quoteShell(joinPath("build", "evaluation", "parallel.txt"))
  for p in A:
    exec quoteShell(programPath(p))

proc otterGateScript(): string =
  var
    t: string = firstExisting([
      "../Otter-RepoEvaluation/tools/agent_hooks/otter-gate.sh",
      "submodules/Otter-RepoEvaluation/tools/agent_hooks/otter-gate.sh"])
  if t.len == 0:
    stop("Otter-RepoEvaluation not found beside this repo or in submodules/.")
  result = t

sharedTask runTests, "Run every evaluation/tests/**/test*.nim":
  compileAndRun(programsIn("evaluation/tests", "test"))

sharedTask test, "Run the tests (same as runTests)":
  compileAndRun(programsIn("evaluation/tests", "test"))

sharedTask runBenchmarks, "Run every evaluation/benchmarks/**/bench*.nim":
  compileAndRun(programsIn("evaluation/benchmarks", "bench"))

sharedTask runStatistics, "Run every evaluation/statistics/**/stat*.nim":
  compileAndRun(programsIn("evaluation/statistics", "stat"))

sharedTask runExamples, "Run every examples/**/*.nim":
  compileAndRun(programsIn("examples", ""))

sharedTask evaluate, "Measure the repo with Otter now (secrets, nesting, roles, layout)":
  exec "sh " & quoteShell(otterGateScript()) & " --force ."
