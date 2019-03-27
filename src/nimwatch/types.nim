import asyncdispatch
when defined(windows):
  import windows

type
  FD* = cint
  WD* = cint
  Watcher* = ref object
    target*: string
    callbacks*: seq[proc (action: FileAction) {.gcsafe.}]
    when defined(windows):
      fd*: AsyncFD
    elif defined(unix):
      fd*: AsyncFD
      wd*: WD
  FileActionKind* = enum
    actionCreate
    actionDelete
    actionModify
    actionMoveFrom
    actionMoveTo
  FileAction* = object
    kind*: FileActionKind
    filename*: string

converter toFD*(fd: AsyncFD): FD = FD(fd)
converter toAsyncFD*(fd: FD): AsyncFD = AsyncFD(fd)
