
import windows
import types

const FILE_ACTION_ADDED* = 0x00000001
const FILE_ACTION_REMOVED* = 0x00000002
const FILE_ACTION_MODIFIED* = 0x00000003
const FILE_ACTION_RENAMED_OLD_NAME* = 0x00000004
const FILE_ACTION_RENAMED_NEW_NAME* = 0x00000005

type
  FileNameArray* {.unchecked.} = array[0..0, Utf16Char]
  FILE_NOTIFY_INFORMATION* {.packed.} = object
    NextEntryOffset*: DWORD
    Action*: DWORD
    FileNameLength*: DWORD
    FileName*: FileNameArray

converter toWINBOOL*(b: bool): WINBOOL = cast[WINBOOL](b)
converter toBool*(b: WINBOOL): bool = cast[bool](b)
converter toDWORD*(x: int): DWORD = cast[DWORD](x)

proc ReadDirectoryChangesW*(
  hDirectory: HANDLE,
  lpBuffer: LPVOID, 
  nBufferLength: DWORD, 
  bWatchSubtree: WINBOOL, 
  dwNotifyFilter: DWORD,
  lpBytesReturned: LPDWORD, 
  lpOverlapped: LPOVERLAPPED, 
  lpCompletionRoutine: LPOVERLAPPED_COMPLETION_ROUTINE,
): WINBOOL {.cdecl, importc, header: "<windows.h>".}

proc readEvents*(hDir: HANDLE): seq[FileAction] =
  var buf: array[10, FILE_NOTIFY_INFORMATION]
  var pBuf = buf[0].addr

  let filter =
    FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_DIR_NAME or FILE_NOTIFY_CHANGE_ATTRIBUTES or FILE_NOTIFY_CHANGE_SIZE or FILE_NOTIFY_CHANGE_LAST_WRITE
  var bytesReturned: DWORD

  discard ReadDirectoryChangesW(hDir, cast[LPVOID](pBuf), sizeof(FILE_NOTIFY_INFORMATION) * 10, true, filter, cast[LPDWORD](bytesReturned.addr), cast[LPOVERLAPPED](nil), cast[LPOVERLAPPED_COMPLETION_ROUTINE](nil))

  var pData = cast[ptr FILE_NOTIFY_INFORMATION](pBuf)
  result = @[]
  while true:
    var action: FileAction

    case pData[].Action
    of FILE_ACTION_ADDED:
      action.kind = actionCreate
    of FILE_ACTION_REMOVED:
      action.kind = actionDelete
    of FILE_ACTION_MODIFIED:
      action.kind = actionModify
    of FILE_ACTION_RENAMED_OLD_NAME:
      action.kind = actionMoveFrom
    of FILE_ACTION_RENAMED_NEW_NAME:
      action.kind = actionMoveTo
    else:
      discard

    let lenBytes = pData[].FileNameLength
    var filename = newWideCString("", lenBytes div 2)
    for i in 0..<(lenBytes div 2):
      filename[i] = pData[].FileName[i]
    action.filename = $filename
    result.add(action)

    if pData[].NextEntryOffset == 0:
      break
    pData = cast[ptr FILE_NOTIFY_INFORMATION](cast[DWORD](pData) + pData[].NextEntryOffset)

#
# Watcher
#

proc init*(watcher: Watcher) =
  watcher.hDir = CreateFile(
    cast[LPCSTR](watcher.target.cstring), 
    FILE_LIST_DIRECTORY,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, 
    cast[LPSECURITY_ATTRIBUTES](nil),
    OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OVERLAPPED,
    cast[HANDLE](nil)
  )
  if watcher.hDir == INVALID_HANDLE_VALUE:
    raise newException(IOError, "not existing file or directory: " & watcher.target)

proc wait*(watcher: Watcher): seq[FileAction] =
  return readEvents(watcher.hDir)

# TODO:
proc close*(watcher: Watcher) =
  discard CloseHandle(watcher.hDir)
