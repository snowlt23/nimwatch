
import asyncdispatch
import threadpool
import types

when defined(windows):
  import winnotify
elif defined(unix):
  import inotify

proc newWatcher*(target: string): Watcher =
  new result
  result.callbacks = @[]
  when defined(windows):
    result.hDir = CreateFile(
      cast[LPCSTR](target.cstring), 
      FILE_LIST_DIRECTORY,
      FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, 
      cast[LPSECURITY_ATTRIBUTES](nil),
      OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OVERLAPPED,
      cast[HANDLE](nil)
    )
    if result.hDir == INVALID_HANDLE_VALUE:
      raise newException(IOError, "not existing file or directory: " & target)
  elif defined(linux):
    result.fd = inotify_init()
    discard inotify_add_watch(result.fd, target, DefaultEvents)

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
