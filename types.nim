
when defined(windows):
  import windows

type
  WatchChannel* = Channel[FileAction]
  Watcher* = ref object
    target*: string
    callbacks*: seq[proc (action: FileAction)]
    when defined(windows):
      hDir*: HANDLE
    elif defined(unix):
      fd*: cint
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
