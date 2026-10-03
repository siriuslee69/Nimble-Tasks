## parallelBuild.nim - runs a list of build commands side by side.
##
##   evaluation.nims writes      this program                     back in evaluation.nims
##   ---------------------       -----------------------------    -----------------------
##   build/evaluation/           runs up to N commands at once    runs the built tests ONE
##     parallel.txt              (N = CPU cores), each one's      AT A TIME, in order
##     (one command per line)    output into its own .log
##
## Why only BUILDS run together: a test program may open a socket or use a
## fixed temp folder, so two tests running at once could fail for no reason
## of their own. Building them never touches those, and building is where
## nearly all the time goes (one `nim c` per test file, 15-30 s each).
##
## Each command line is "<log file>\t<command>". A failed command prints its
## log; the exit code is 1 when any command failed, 0 otherwise.
##
##   parallelBuild build/evaluation/parallel.txt

import std/[os, osproc, strutils]
import runePragmas

type
  Job {.role: preparedData, expectedCount: [0, 500], lifeCycle: lcJob.} = object
    ## log: where the command's output goes. command: the shell line to run.
    log: string
    command: string

proc readJobs(path: string): seq[Job] {.role: parser.} =
  ## path: the job list. Blank lines are skipped.
  var
    parts: seq[string] = @[]
  for line in readFile(path).splitLines():
    parts = line.split('\t', 1)
    if parts.len == 2 and parts[1].strip().len > 0:
      result.add Job(log: parts[0], command: parts[1])

proc runAll(J: seq[Job]): int {.role: orchestrator.} =
  ## J: jobs; returns how many failed. Output goes to each job's log through
  ## the shell, so a chatty build can never fill a pipe and stall.
  var
    lines: seq[string] = @[]
    failed: int = 0
  for j in J:
    lines.add j.command & " > " & quoteShell(j.log) & " 2>&1"
  discard execProcesses(lines, {poEvalCommand}, countProcessors(),
    afterRunEvent = proc (i: int, p: Process) =
      if p.peekExitCode() == 0:
        echo "built  ", J[i].log.splitFile().name
      else:
        failed = failed + 1
        echo "FAILED ", J[i].log.splitFile().name
        echo readFile(J[i].log))
  result = failed

when isMainModule:
  if paramCount() != 1 or not fileExists(paramStr(1)):
    quit("usage: parallelBuild <job list>", 2)
  if runAll(readJobs(paramStr(1))) > 0:
    quit(1)
