# TODO

One item per problem (WORKFLOW.md section 8). Done items are REMOVED and named in PROGRESS.md.

- [ ] The parallel build helper (build/nimbleTasksParallelBuild) is rebuilt only when its source text changes, not when the compiler or glibc changes.
  why: after a system update the old helper dies with `symbol lookup error: /usr/lib/libc.so.6: undefined symbol: __pointer_chk_guard`, and every `nimble test` of every repo stops there until someone moves the file aside by hand (happened 2026-11-20)
  start: build/nimbleTasksParallelBuild /dev/null   (after a glibc update, with an old build/ folder)
  done when: `parallelHelper()` in src/tasks/evaluation.nims also rebuilds when the helper cannot start (run it once with no arguments; a crash or "symbol lookup" means rebuild), and a test copies a broken file over the helper and still passes
  needs: nobody
  plan: stamp the .src copy with `nim --version` plus the path of the compiler, or run `helper --version` first and rebuild on any failure to start
