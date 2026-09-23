## ---------------------------------------------------------------------------
## Nimble-Tasks <- the ONE file a repo includes to get every shared task
## ---------------------------------------------------------------------------
##
## In a repo's .nimble file, after its own settings:
##
##     when fileExists(thisDir() & "/../Nimble-Tasks/src/nimbleTasks.nims"):
##       include "../Nimble-Tasks/src/nimbleTasks.nims"
##     elif fileExists(thisDir() & "/submodules/Nimble-Tasks/src/nimbleTasks.nims"):
##       include "submodules/Nimble-Tasks/src/nimbleTasks.nims"
##     else:
##       {.error: "Nimble-Tasks not found: git submodule update --init submodules/Nimble-Tasks".}
##
## The sibling clone wins, so an edit there reaches every repo beside it at
## once. The submodule is what a fresh clone somewhere else falls back on.
##
##   core.nims        names list, hint line, sharedTask, entry lookup
##   git.nims         autopush, switch, applyNightly, mainToNightlySnap
##   submodules.nims  updateSubmodules, submoduleStatus, find
##   android.nims     buildAndroid, installAndroid
##   frontends.nims   run/build Webui, Cli, Tui, Owl, Server, buildAll
##   evaluation.nims  test, runTests, runBenchmarks, runStatistics,
##                    runExamples, evaluate
##   (this file)      clean, sharedTasks

include "tasks/core.nims"

hint()

include "tasks/git.nims"
include "tasks/submodules.nims"
include "tasks/android.nims"
include "tasks/frontends.nims"
include "tasks/evaluation.nims"

sharedTask clean, "Delete build/ and nimcache/":
  for d in ["build", "nimcache"]:
    if dirExists(d):
      rmDir(d)
      echo "Removed " & d & "/"

sharedTask sharedTasks, "List the tasks that come from Nimble-Tasks":
  echo "Shared tasks (Nimble-Tasks at " & nimbleTasksDir & "):"
  for t in sharedTaskNames:
    echo "  " & t & (if normalize(t) in repoOwnTasks: "   <- replaced by this repo" else: "")
