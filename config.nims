## Shared pragmas: one file for the whole workspace, never copied.
if dirExists(thisDir() & "/../Rune-Pragmas/meta"):
  switch("path", thisDir() & "/../Rune-Pragmas/meta")
if dirExists(thisDir() & "/submodules/Rune-Pragmas/meta"):
  switch("path", thisDir() & "/submodules/Rune-Pragmas/meta")
