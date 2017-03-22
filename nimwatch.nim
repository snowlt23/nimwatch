
import threadpool
import types

when defined(windows):
  import winnotify
elif defined(unix):
  import inotify

proc newWatcher*(target: string): Watcher =
  new result
  result.target = target
  result.callbacks = @[]
  result.init()

proc register*(watcher: Watcher, cb: proc (action: FileAction)) =
  watcher.callbacks.add(cb)

proc watchWithThread*(watcher: Watcher) {.thread.} =
  while true:
    for action in watcher.wait():
      for cb in watcher.callbacks:
        cb(action)
proc watch*(watcher: Watcher) =
  spawn watcher.watchWithThread()

proc watchForever*() =
  while true:
    sync()

when isMainModule:
  let watcher = newWatcher("./testdir")
  watcher.register do (action: FileAction):
    echo action
  watcher.watch()
  watchForever()
