
import types
export types
import asyncdispatch

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

proc watch*(watcher: Watcher) =
  var fut = watcher.read()
  fut.callback = proc () =
    for cb in watcher.callbacks:
      for action in fut.read():
        cb(action)
    watcher.watch()

when isMainModule:
  let watcher = newWatcher("./testdir")
  watcher.register do (action: FileAction):
    echo action
  watcher.watch()
  runForever()
