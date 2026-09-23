## ---------------------------------------------------------------------------
## preset <- build a repo from ONE .toml file instead of a long flag list
## ---------------------------------------------------------------------------
##
## Included by a repo's `config.nims` (not by the .nimble file):
##
##     when fileExists(thisDir() & "/../Nimble-Tasks/src/preset.nims"):
##       include "../Nimble-Tasks/src/preset.nims"
##     elif fileExists(thisDir() & "/submodules/Nimble-Tasks/src/preset.nims"):
##       include "submodules/Nimble-Tasks/src/preset.nims"
##     applyPreset()
##
## Then:
##
##     nim c app.nim                    configs/default.toml
##     nim c -d:preset=iot app.nim      default.toml, then iot.toml over it
##     nim c -d:preset=my/own.toml ...  that file
##     nimble buildCli -d:preset=iot    the same; shared tasks pass it on
##
## What a preset file may hold -- four sections, every one optional:
##
##   section    line in the file             becomes
##   ---------  ---------------------------  ------------------------------
##   [nim]      opt = "size"                 --opt:size
##              panics = true                --panics:on   (false -> off)
##   [define]   bifrostKems = "kyber,x25519" -d:bifrostKems=kyber,x25519
##              danger = true                -d:danger     (false -> not set)
##              saberMaxRank = 2             -d:saberMaxRank=2
##              bifrostSigs = ""             not set: "" means the default
##   [passC]    flags = ["-flto"]            --passC:-flto
##   [passL]    flags = ["-flto"]            --passL:-flto
##
## [project] (name, version, ...) is read by `projectValue` below, for the
## .nimble file and nix -- only ever from default.toml.
##
## Any other section ([preset], [runtime], ...) is left alone here; the nix
## module and the program's own config parser read those.
## The program can find them: the files applied are handed on as
## `-d:presetFiles=configs/default.toml;configs/iot.toml` (base first).
##
## Who wins between files: the later one, key by key. `configs/iot.toml`
## setting `flags = [...]` in [passC] replaces default.toml's list.
##
## Who wins over every file: the command line.
## `nim c -d:preset=iot -d:bifrostKems=kyber` takes everything from iot.toml
## except bifrostKems. Nim applies the command line after config.nims, so
## this needs nothing from this file.
##
## The TOML understood here is the plain subset presets need: `[section]`,
## `key = value` with a "string", a whole number, true/false, or a list of
## strings (it may run over several lines), and `#` comments. Anything else
## stops the build with the line number, rather than being guessed at.
##
## Every name here starts with `preset` so it cannot collide with the
## including config.nims.

import std/[os, strutils]

type
  PresetEntry = tuple[section, key, value: string, list: seq[string]]
    ## One `key = value` line. `list` is filled only for `[...]` values.

var
  presetEntries: seq[PresetEntry] = @[]
  presetFile: string = ""
  presetFilesLoaded: seq[string] = @[]
    ## Every file applied, base first. Handed to the program as
    ## -d:presetFiles=a.toml;b.toml so its own code can read the sections
    ## this file leaves alone (e.g. a pinned algorithm layout).

proc presetStop(msg: string) =
  ## msg: why the build cannot go on; printed with the file it came from.
  quit("preset " & presetFile & ": " & msg, 1)

proc presetStripComment(line: string): string =
  ## line: one raw line -> the same line without its `#` comment. A `#`
  ## inside a "string" is kept.
  var
    inString: bool = false
    i: int = 0
  while i < line.len:
    if line[i] == '"':
      inString = not inString
    if line[i] == '#' and not inString:
      return line[0 ..< i].strip()
    i = i + 1
  result = line.strip()

proc presetUnquote(s: string, n: int): string =
  ## s/n: one value and its line number -> the plain text. "x" -> x;
  ## numbers and true/false stay as written.
  if s.len >= 2 and s[0] == '"' and s[^1] == '"':
    return s[1 .. ^2]
  if s in ["true", "false"] or (s.len > 0 and s.replace("_", "").allCharsInSet(
      {'0' .. '9', '-'})):
    return s.replace("_", "")
  presetStop("line " & $n & ": value must be \"text\", a number, true or " &
    "false, got: " & s)

proc presetList(s: string, n: int): seq[string] =
  ## s/n: `["a", "b"]` and its line number -> @["a", "b"]. Only commas
  ## OUTSIDE quotes separate items: "-Wl,--gc-sections" stays one item.
  var
    inner: string = s[1 .. ^2]
    part: string = ""
    inString: bool = false
    i: int = 0
  while i <= inner.len:
    if i == inner.len or (inner[i] == ',' and not inString):
      if part.strip().len > 0:
        result.add(presetUnquote(part.strip(), n))
      part = ""
    else:
      inString = inString xor (inner[i] == '"')
      part.add(inner[i])
    i = i + 1

proc presetJoinList(pending: var tuple[key, value: string], line,
    section: string, n: int) =
  ## pending/line/section/n: one more line of a list that began on an
  ## earlier line; the entry is stored once its closing `]` arrives.
  pending.value = pending.value & " " & line
  if line.endsWith("]"):
    presetEntries.add((section, pending.key, "", presetList(pending.value, n)))
    pending = ("", "")

proc presetParse(text: string) =
  ## text: a whole preset file -> presetEntries.
  var
    section: string = ""
    line: string = ""
    n: int = 0
    eq: int = 0
    key: string = ""
    value: string = ""
    pending: tuple[key, value: string] = ("", "")
  for raw in text.splitLines():
    n = n + 1
    line = presetStripComment(raw)
    if line.len == 0:
      continue
    if pending.key.len > 0:
      presetJoinList(pending, line, section, n)
      continue
    if line[0] == '[' and line[^1] == ']':
      section = line[1 .. ^2].strip()
      continue
    eq = line.find('=')
    if eq < 1:
      presetStop("line " & $n & ": expected `key = value`, got: " & line)
    key = line[0 ..< eq].strip()
    value = line[eq + 1 .. ^1].strip()
    if value.startsWith("[") and not value.endsWith("]"):
      pending = (key, value)
      continue
    if value.startsWith("[") and value.endsWith("]"):
      presetEntries.add((section, key, "", presetList(value, n)))
    else:
      presetEntries.add((section, key, presetUnquote(value, n), @[]))
  if pending.key.len > 0:
    presetStop("list `" & pending.key & "` is never closed with ]")

proc presetCommandDefine(name: string): string =
  ## name: a define looked up on the command line -> its value, or "".
  var
    i: int = 1
    arg: string = ""
  while i <= paramCount():
    arg = paramStr(i)
    for prefix in ["-d:", "--define:", "--d:"]:
      if arg.startsWith(prefix & name & "=") or arg.startsWith(prefix & name & ":"):
        return arg[prefix.len + name.len + 1 .. ^1]
    i = i + 1

proc presetResolve(name: string): string =
  ## name: "iot" -> configs/iot.toml; anything with a / or ending in .toml
  ## is taken as a path (relative to the repo root).
  if name.contains('/') or name.contains('\\') or name.endsWith(".toml"):
    result = if isAbsolute(name): name else: thisDir() / name
  else:
    result = thisDir() / "configs" / (name & ".toml")

proc presetValue(section, key, fallback: string): string =
  ## section/key/fallback: one value from the loaded preset, or fallback
  ## when the preset does not set it (or sets it to "").
  result = fallback
  for e in presetEntries:
    if e.section == section and e.key == key and e.value.len > 0:
      result = e.value

proc presetApplyEntry(e: PresetEntry) =
  ## e: one entry -> the compiler switch(es) it stands for.
  case e.section
  of "nim":
    case e.value
    of "true": switch(e.key, "on")
    of "false": switch(e.key, "off")
    else: switch(e.key, e.value)
  of "define":
    case e.value
    of "", "false": discard
    of "true": switch("define", e.key)
    else: switch("define", e.key & "=" & e.value)
  of "passC", "passL":
    for flag in e.list:
      switch(e.section, flag)
  else:
    discard

proc presetIsLast(i: int): bool =
  ## i: index of an entry -> true when no later entry sets the same key in
  ## the same section. A named preset replaces a base value key by key --
  ## lists included -- the same rule nix's recursiveUpdate follows.
  var
    j: int = i + 1
  while j < presetEntries.len:
    if presetEntries[j].section == presetEntries[i].section and
        presetEntries[j].key == presetEntries[i].key:
      return false
    j = j + 1
  result = true

proc presetApplySection(section: string) =
  ## section: applies the winning entry of every key in that one section.
  var
    i: int = 0
  while i < presetEntries.len:
    if presetEntries[i].section == section and presetIsLast(i):
      presetApplyEntry(presetEntries[i])
    i = i + 1

proc presetLoad(path: string) =
  ## path: one preset file -> its entries appended after any already loaded.
  presetFile = path
  presetFilesLoaded.add(path)
  presetParse(readFile(path))

proc applyPreset(base: string = "default") =
  ## base: the preset every build starts from (configs/default.toml). A
  ## preset named with -d:preset= is laid OVER it: what the named file sets
  ## wins, everything else keeps the base value.
  ##
  ##   configs/default.toml  -->  configs/iot.toml  -->  command line
  ##   (every switch)            (what iot changes)     (wins over both)
  ##
  ## A named preset that does not exist stops the build; a repo without a
  ## base file builds as before.
  var
    named: string = presetCommandDefine("preset")
    basePath: string = presetResolve(base)
  if fileExists(basePath):
    presetLoad(basePath)
  if named.len > 0 and not fileExists(presetResolve(named)):
    quit("-d:preset=" & named & ": no such file " & presetResolve(named), 1)
  if named.len > 0 and presetResolve(named) != basePath:
    presetLoad(presetResolve(named))
  ## Defines first: `-d:danger` and `-d:release` quietly reset the
  ## optimisation to speed, so a preset's own `opt = "size"` must come after.
  for section in ["define", "nim", "passC", "passL"]:
    presetApplySection(section)
  if presetFilesLoaded.len > 0:
    switch("define", "presetFiles=" & presetFilesLoaded.join(";"))

proc projectValue(key: string): string =
  ## key: one value of the [project] table in configs/default.toml -- the
  ## ONE place a repo's name, version, description, license and author are
  ## written. The .nimble file reads them from here, and nix/package.nix
  ## reads the same table with builtins.fromTOML:
  ##
  ##   # top of the .nimble file
  ##   include "../Nimble-Tasks/src/preset.nims"   (or the submodule path)
  ##   version     = projectValue("version")
  ##   description = projectValue("description")
  ##
  ## Only default.toml is read: a named preset changes how a build is made,
  ## never which project it is. A missing key stops with the file name.
  var
    path: string = presetResolve("default")
    kept: int = presetEntries.len
  if not fileExists(path):
    quit("projectValue: " & path & " is missing; it holds [project]", 1)
  presetFile = path
  presetParse(readFile(path))
  for e in presetEntries[kept .. ^1]:
    if e.section == "project" and e.key == key:
      result = e.value
  presetEntries.setLen(kept)
  if result.len == 0:
    quit("projectValue: [project] " & key & " is not set in " & path, 1)
