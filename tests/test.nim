import ../src/nimwatch
import unittest
import macros
import os
import asyncdispatch

var running = true
var watchNum {.compileTime.} = 0
var watchCount = 0
macro watchtest(e): untyped =
  result = quote do:
    if watchCount == `watchNum`:
      `e`
      watchCount.inc
      return
  watchNum.inc
macro watchend(): untyped =
  result = quote do:
    if watchCount == `watchNum`:
      running = false
      return

suite "nimwatch":
  test "file":
    removeDir("testdir")
    createDir("testdir")
    let watcher = newWatcher("testdir")
    watcher.register do (action: FileAction):
      watchtest:
        check(action.kind == actionCreate)
        check(action.filename == "abc.txt")
      watchtest:
        check(action.kind == actionModify)
        check(action.filename == "abc.txt")
      watchtest:
        check(action.kind == actionCreate)
        check(action.filename == "oh.txt")
      watchtest:
        check(action.kind == actionModify)
        check(action.filename == "oh.txt")
      watchtest:
        check(action.kind == actionModify)
        check(action.filename == "abc.txt")
      watchtest:
        check(action.kind == actionDelete)
        check(action.filename == "abc.txt")
      watchend
    watcher.watch()
    addTimer(500, true) do (fd: AsyncFD) -> bool:
      drain()
      writeFile("testdir/abc.txt", "ABC")
      drain()
      writeFile("testdir/oh.txt", "triple")
      drain()
      writeFile("testdir/abc.txt", readFile("testdir/abc.txt") & "DEF")
      drain()
      removeFile("testdir/abc.txt")
      drain()
      writeFile("testdir/end.txt", "")
      drain()
      return true
    while running:
      poll()
