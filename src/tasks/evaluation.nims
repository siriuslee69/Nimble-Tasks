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

proc compileAndRun(A: seq[string]) =
  ## A: Nim programs; each is compiled and run, the first failure stops.
  mkDir(joinPath("build", "evaluation"))
  for p in A:
    exec "nim c -r " & overrideOf(nimFlags) & " --hints:off -o:" &
      quoteShell(joinPath("build", "evaluation", exeName(splitFile(p).name))) &
      " " & quoteShell(p)

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
