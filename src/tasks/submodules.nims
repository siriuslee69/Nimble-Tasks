## ---------------------------------------------------------------------------
## submodules <- keep every submodule on the newest commit of its main branch
## ---------------------------------------------------------------------------
##
##   updateSubmodules  for each submodule:
##
##       refuse if it has uncommitted work
##         -> fetch origin
##         -> pick the branch: .gitmodules `branch = …`, else main,
##            else master, else whatever origin calls its default
##         -> check out that branch's newest commit
##         -> bring its own nested submodules to their pins
##         -> stage the new pin
##       then ONE commit "Pin submodules to newest main" (no push)
##
##     A repo keeps a submodule where it is with:
##
##       const
##         frozenSubmodules: array[1, string] = ["submodules/zstd"]
##
##   submoduleStatus   which commit each submodule is pinned to
##   find              point submodules at sibling clones in the parent folder

proc submodulePaths(): seq[string] =
  ## Every `path = …` line of .gitmodules, in file order.
  var
    T: seq[string] = @[]
    raw: string = ""
  if not fileExists(".gitmodules"):
    return T
  raw = captureGit("config -f .gitmodules --get-regexp path").strip()
  for line in raw.splitLines:
    T.add(line.split(' ', maxsplit = 1)[^1].strip())
  result = T

proc submoduleName(p: string): string =
  ## p: submodule path; returns its [submodule "name"] from .gitmodules.
  var
    raw: string = captureGit("config -f .gitmodules --get-regexp path").strip()
    t: string = ""
  for line in raw.splitLines:
    if t.len == 0 and line.endsWith(" " & p):
      t = line.split(' ', maxsplit = 1)[0]
  if t.len == 0:
    stop(p & " is not listed in .gitmodules.")
  result = t[len("submodule.") .. t.len - len(".path") - 1]

proc isFrozen(p: string): bool =
  result = false
  when declared(frozenSubmodules):
    result = p in frozenSubmodules

proc gitIn(p, args: string): string =
  ## p: folder the git command runs in
  result = captureGit("-C " & quoteShell(p) & " " & args).strip()

proc hasRemoteBranch(p, b: string): bool =
  result = gitRaw("-C " & quoteShell(p) &
    " rev-parse --verify --quiet refs/remotes/origin/" & b).exitCode == 0

proc pinBranch(p: string): string =
  ## p: submodule path; the branch whose newest commit it gets pinned to.
  var
    configured: string = gitRaw("config -f .gitmodules submodule." &
      submoduleName(p) & ".branch").output.strip()
    t: string = ""
  if configured.len > 0 and configured != ".":
    t = configured
  elif hasRemoteBranch(p, "main"):
    t = "main"
  elif hasRemoteBranch(p, "master"):
    t = "master"
  else:
    t = gitIn(p, "symbolic-ref --short refs/remotes/origin/HEAD").replace("origin/", "")
  result = t

proc pinToNewest(p: string) =
  ## p: submodule path; moves it to its pin branch's newest commit.
  var
    before: string = gitIn(p, "rev-parse --short HEAD")
    b: string = ""
  if gitIn(p, "status --porcelain").len > 0:
    stop(p & " has uncommitted work. Commit it inside the submodule first.")
  exec "git -C " & quoteShell(p) & " fetch --quiet origin"
  b = pinBranch(p)
  exec "git -C " & quoteShell(p) & " checkout --quiet --detach origin/" & b
  exec "git -C " & quoteShell(p) & " submodule update --quiet --init --recursive"
  exec "git add " & quoteShell(p)
  echo "  " & p & "  " & before & " -> " & gitIn(p, "rev-parse --short HEAD") &
    "  (origin/" & b & ")"

sharedTask updateSubmodules, "Pin every submodule to the newest commit of its main branch":
  var
    P: seq[string] = submodulePaths()
  if P.len == 0:
    stop("No .gitmodules found - this repo has no submodules to update.")
  exec "git submodule update --quiet --init"
  for p in P:
    if isFrozen(p):
      echo "  " & p & "  frozen, left as is"
    else:
      pinToNewest(p)
  if captureGit("diff --cached --name-only -- " & P.join(" ")).strip().len == 0:
    echo "All submodules already sit on their newest commit."
  else:
    exec "git commit --quiet -m \"Pin submodules to newest main\" -- " & P.join(" ")
    echo "Committed the new pins. Push with `nimble autopush` or `git push`."

sharedTask submoduleStatus, "Show which commit every submodule is pinned to":
  exec "git submodule status --recursive"

sharedTask find, "Use local clones for submodules in parent folder":
  var
    P: seq[string] = submodulePaths()
    root: string = parentDir(getCurrentDir())
    localDir: string = ""
    name: string = ""
  if P.len == 0:
    stop("No .gitmodules found.")
  for p in P:
    localDir = joinPath(root, splitPath(p).tail).replace('\\', '/')
    name = submoduleName(p)
    if dirExists(localDir):
      exec "git config -f .gitmodules submodule." & name & ".url " & localDir
      exec "git config submodule." & name & ".url " & localDir
  exec "git submodule sync --recursive"
