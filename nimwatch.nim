
import windows
import asyncdispatch

type
  Watcher* = ref object
    target*: string
    hDir*: HANDLE
  FileActionKind* = enum
    actionAdd
    actionRemove
    actionModify
    actionRenameOld
    actionRenameNew
  FileAction* = object
    kind*: FileActionKind
    filename*: string

type
  FILE_NOTIFY_INFORMATION* = object
    NextEntryOffset*: DWORD
    Action*: DWORD
    FileNameLength*: DWORD
    FileName*: seq[WCHAR]

const FILE_ACTION_ADDED = 0x00000001
const FILE_ACTION_REMOVED = 0x00000002
const FILE_ACTION_MODIFIED = 0x00000003
const FILE_ACTION_RENAMED_OLD_NAME = 0x00000004
const FILE_ACTION_RENAMED_NEW_NAME = 0x00000005

converter toWINBOOL(b: bool): WINBOOL = cast[WINBOOL](b)
converter toBool(b: WINBOOL): bool = cast[bool](b)
converter toDWORD(x: int): DWORD = cast[DWORD](x)

proc ReadDirectoryChangesW*(
  hDirectory: HANDLE,
  lpBuffer: LPVOID, 
  nBufferLength: DWORD, 
  bWatchSubtree: WINBOOL, 
  dwNotifyFilter: DWORD,
  lpBytesReturned: LPDWORD, 
  lpOverlapped: LPOVERLAPPED, 
  lpCompletionRoutine: LPOVERLAPPED_COMPLETION_ROUTINE,
): WINBOOL {.importc.}

proc newWatcher*(target: string): Watcher =
  new result
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

proc watch*(watcher: Watcher): Future[seq[FileAction]] {.async.} =
  var buf: array[10, FILE_NOTIFY_INFORMATION]
  var pBuf = buf[0].addr

  let filter =
    FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_DIR_NAME or FILE_NOTIFY_CHANGE_ATTRIBUTES or FILE_NOTIFY_CHANGE_SIZE or FILE_NOTIFY_CHANGE_LAST_WRITE
  let hEvent = CreateEvent(cast[LPSECURITY_ATTRIBUTES](nil), true, false, cast[LPCSTR](nil))
  discard ResetEvent(hEvent)
  var olp: OVERLAPPED
  olp.hEvent = hEvent

  if not ReadDirectoryChangesW(watcher.hDir, cast[LPVOID](pBuf), sizeof(FILE_NOTIFY_INFORMATION) * 10, true, filter, cast[LPDWORD](nil), cast[LPOVERLAPPED](olp.addr), cast[LPOVERLAPPED_COMPLETION_ROUTINE](nil)):
    raise newException(IOError, "couldn't watch directory changes")
  while true:
    let waitResult = WaitForSingleObject(hEvent, 500)
    if waitResult != WAIT_TIMEOUT:
      break
    echo "."

  var retsize: DWORD
  if not GetOverlappedResult(watcher.hDir, olp, retsize, false):
    raise newException(IOError, "couldn't get overlapped result")

  var pData = cast[ptr FILE_NOTIFY_INFORMATION](pBuf)
  result = @[]
  while true:
    var action: FileAction

    case pData[].Action
    of FILE_ACTION_ADDED:
      action.kind = actionAdd
    of FILE_ACTION_REMOVED:
      action.kind = actionRemove
    of FILE_ACTION_MODIFIED:
      action.kind = actionModify
    of FILE_ACTION_RENAMED_OLD_NAME:
      action.kind = actionRenameOld
    of FILE_ACTION_RENAMED_NEW_NAME:
      action.kind = actionRenameNew
    else:
      discard

    let lenBytes = pData[].FileNameLength
    var filename = newWideCString("", lenBytes)
    for i in 0..<lenBytes:
      filename[i] = cast[Utf16Char](pData[].FileName[i])
    action.filename = $filename
    result.add(action)

    if pData[].NextEntryOffset == 0:
      break
    pData = cast[ptr FILE_NOTIFY_INFORMATION](cast[DWORD](pData) + pData[].NextEntryOffset)
      
let watcher = newWatcher("./testdir")
let ret = waitFor watcher.watch()
echo ret
