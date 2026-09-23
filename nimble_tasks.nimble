## Nimble-Tasks runs its own shared tasks, so every change is tried here
## first: `nimble test` builds throwaway repos and drives them with nimble.

version       = "0.1.0"
author        = "siriuslee69"
description   = "Shared nimble tasks (git flow, submodules, frontends, evaluation) for every repo"
license       = "Unlicense"
srcDir        = "src"

requires "nim >= 2.0.0"

include "src/nimbleTasks.nims"
