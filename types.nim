
import asyncdispatch
when defined(windows):
  import windows

type
  WatchChannel* = Channel[FileAction]
  Watcher* = ref object
    target*: string
    callbacks*: seq[proc (action: FileAction)]
    when defined(windows):
      fd*: AsyncFD
    elif defined(unix):
      fd*: AsyncFD
      wd*: cint
  FileActionKind* = enum
    actionCreate
    actionDelete
    actionModify
    actionMoveFrom
    actionMoveTo
  FileAction* = object
    kind*: FileActionKind
    filename*: string
