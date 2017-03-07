
import windows
import asyncdispatch

type
  Watcher = ref object
    hNotif: HANDLE
    path*: string
    callbacks*: seq[proc ()]

proc newWatcher*(path: string): Watcher =
  new result
  let filter = FILE_NOTIFY_CHANGE_LAST_WRITE
  result.hNotif = windows.FindFirstChangeNotification(cast[LPCSTR](path.cstring), cast[WINBOOL](true), cast[DWORD](filter))
  result.path = path
  if result.hNotif == INVALID_HANDLE_VALUE:
    raise newException(IOError, "couldnt start watch in: " & path)

proc wait*(watcher: Watcher) =
  discard windows.WaitForSingleObject(watcher.hNotif, INFINITE)
  discard windows.FindNextChangeNotification(watcher.hNotif)

template watch*(path: string, body: untyped) =
  let watcher = newWatcher(path)
  while true:
    watcher.wait()
    body

when isMainModule:
  watch "./":
    echo "detect file changes!"
