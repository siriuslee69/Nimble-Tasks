## ---------------------------------------------------------------------------
## git <- the day-to-day branch flow every repo shares
## ---------------------------------------------------------------------------
##
##   nightly  <- where work happens
##   main     <- the tested state
##
##   autopush          stage all, refuse build output, commit with the
##                     message from agents/PROGRESS.md, push
##   switch            toggle the checkout between nightly and main
##   applyNightly      move main forward to nightly (fast-forward only)
##   mainToNightlySnap give nightly main's files, keep nightly's history:
##
##       nightly: A -- B -- C -- S   <- S holds main's files, parents C and M
##       main:    ...........M --'

proc resolveProgressPath(): string =
  var
    t: string = firstExisting(["agents/PROGRESS.md", "agents/progress.md"])
  if t.len == 0:
    t = "agents/PROGRESS.md"
  result = t

proc resolveCommitMessage(p: string): string =
  ## p: progress file; its "Commit Message:" line becomes the commit text.
  var
    msg: string = ""
  if fileExists(p):
    for line in readFile(p).splitLines:
      if msg.len == 0 and line.startsWith("Commit Message:"):
        msg = line["Commit Message:".len .. ^1].strip()
  if msg.len == 0:
    msg = "No specific commit message given."
  result = msg

proc captureGit(args: string): string =
  ## args: one git subcommand line; output is returned, failure stops.
  var
    t: tuple[output: string, exitCode: int] = gitRaw(args)
  if t.exitCode != 0:
    stop("git " & args & " failed:\n" & t.output)
  result = t.output

proc isGeneratedOrLocalArtifact(p: string): bool =
  ## p: one staged repo-relative path checked against build/local output.
  ## Repos add their own with `const extraArtifacts = [...]`; each one
  ## matches anywhere in the path ("/.gradle/" catches app/.gradle/x too).
  var
    s: string = p.replace('\\', '/')
    extra: bool = false
  when declared(extraArtifacts):
    for e in extraArtifacts:
      extra = extra or s.contains(e)
  result = extra or splitPath(s).tail.startsWith(".fuse_hidden") or
    s.startsWith("nimcache") or
    s.startsWith("build/") or s.startsWith("builds/") or
    s.startsWith(".gradle/") or s.startsWith(".kotlin/") or
    s.contains("/.gradle/") or s.contains("/.kotlin/") or
    s.endsWith(".exe") or s.endsWith(".dll") or s.endsWith(".so") or
    s.endsWith(".dylib") or s.endsWith(".o") or s.endsWith(".obj") or
    s.endsWith(".a") or s.endsWith(".lib") or s.endsWith(".pdb") or
    s == "local.properties" or s == "userconfig.toml" or
    s == "nimble.paths" or s == "nimble.develop" or
    s.startsWith("agents/.local")

proc behindUpstream(): int =
  ## How many commits the remote branch has that this one lacks; 0 when the
  ## branch has no remote twin yet.
  var
    t: tuple[output: string, exitCode: int] = gitRaw("rev-list --count HEAD..@{u}")
    n: int = 0
  if t.exitCode == 0:
    n = parseInt(t.output.strip())
  result = n

proc firstArtifact(staged: string): string =
  ## staged: newline-separated paths; the first build/local one, or "".
  var
    t: string = ""
  for p in staged.splitLines:
    if t.len == 0 and isGeneratedOrLocalArtifact(p):
      t = p
  result = t

sharedTask autopush, "Add, commit, and push after rejecting generated/local artifacts":
  var
    msgPath: string = joinPath(".git", "autopush-commit-message.txt")
    staged: string = ""
    bad: string = ""
  if fileExists(joinPath(".git", "index.lock")):
    stop("Git lock exists at .git/index.lock. If no Git process is active, remove it and retry.")
  exec "git add -A ."
  staged = captureGit("diff --cached --name-only").strip()
  bad = firstArtifact(staged)
  if bad.len > 0:
    stop("Refusing autopush: generated/local artifact staged: " & bad &
      "\nRemove it from the index or extend .gitignore before committing.")
  if staged.len == 0:
    echo "No staged changes. Skipping commit."
  else:
    writeFile(msgPath, resolveCommitMessage(resolveProgressPath()) & "\n")
    exec "git commit --file " & msgPath
  if captureGit("branch --show-current").strip().len == 0:
    stop("Refusing autopush from a detached HEAD. Check out a branch first.")
  if behindUpstream() > 0:
    exec "git pull --rebase --autostash"
  exec "git push -u origin HEAD"   # -u: also works on a fresh branch

sharedTask switch, "Toggle the working branch between nightly and main":
  var
    branch: string = captureGit("branch --show-current").strip()
    target: string = "nightly"
  if branch == "nightly":
    target = "main"
  echo "Switching from '" &
    (if branch.len > 0: branch else: "(detached HEAD)") &
    "' to '" & target & "'."
  exec "git checkout " & target

sharedTask applyNightly, "Promote nightly onto main by fast-forward and push":
  var
    branch: string = captureGit("branch --show-current").strip()
  if branch == "main":
    stop("On 'main'. Run `nimble switch` to move to nightly before applying.")
  exec "git fetch . nightly:main"
  exec "git push origin nightly:main"
  echo "main is now at the nightly state; nightly branch left intact."

sharedTask mainToNightlySnap, "Replace nightly's files with main's, keeping nightly's history":
  var
    branch: string = captureGit("branch --show-current").strip()
    dirty: string = captureGit("status --porcelain --untracked-files=no").strip()
    snap: string = ""
  if branch == "nightly" and dirty.len > 0:
    stop("Uncommitted changes on nightly. Commit or stash them first.")
  snap = captureGit("commit-tree main^{tree} -p nightly -p main" &
    " -m \"Snapshot main onto nightly\"").strip()
  exec "git update-ref refs/heads/nightly " & snap
  if branch == "nightly":
    exec "git reset --hard nightly"
  exec "git push origin nightly:nightly"
  echo "nightly now matches main; its past commits are kept below " & snap[0 .. 6] & "."
