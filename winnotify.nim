
import windows
import os
import types
import asyncdispatch

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

proc readEvents*(watcher: Watcher, buflen: int): Future[seq[FileAction]] =
  let bufsize = sizeof(FILE_NOTIFY_INFORMATION) * buflen
  var buffer = alloc0(bufsize)

  let filter =
    FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_DIR_NAME or FILE_NOTIFY_CHANGE_ATTRIBUTES or FILE_NOTIFY_CHANGE_SIZE or FILE_NOTIFY_CHANGE_LAST_WRITE
  var bytesReturned: DWORD

  var retFuture = newFuture[seq[FileAction]]("winnotify.readEvents")

  var ol = PCustomOverlapped()
  GC_ref(ol)
  ol.data = CompletionData(fd: watcher.fd, cb:
    proc (fd: AsyncFD, bytesCount: DWORD, errcode: OSErrorCode) =
      if not retFuture.finished:
        if errcode == OSErrorCode(-1):
          var pData = cast[ptr FILE_NOTIFY_INFORMATION](buffer)
          var ret = newSeq[FileAction]()
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
              filename[i] = pData[].Filename[i]
            action.filename = $filename
            
            ret.add(action)

            if pData[].NextEntryOffset == 0:
              break
            pData = cast[ptr FILE_NOTIFY_INFORMATION](cast[DWORD](pData) + pData[].NextEntryOffset)
          retFuture.complete(ret)
        else:
          retFuture.fail(newException(OSError, osErrorMsg(errcode)))
      if buffer != nil:
        dealloc buffer
        GC_unref(ol)
        buffer = nil
  )

  discard ReadDirectoryChangesW(HANDLE(watcher.fd), cast[LPVOID](buffer), bufsize, true, filter, cast[LPDWORD](bytesReturned.addr), cast[LPOVERLAPPED](ol), cast[LPOVERLAPPED_COMPLETION_ROUTINE](nil))

  return retFuture

#
# Watcher
#

proc init*(watcher: Watcher) =
  watcher.fd = AsyncFD(CreateFile(
    cast[LPCSTR](watcher.target.cstring), 
    FILE_LIST_DIRECTORY,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, 
    cast[LPSECURITY_ATTRIBUTES](nil),
    OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OVERLAPPED,
    cast[HANDLE](nil)
  ))
  if HANDLE(watcher.fd) == INVALID_HANDLE_VALUE:
    raise newException(OSError, "not existing file or directory: " & watcher.target)
  register(watcher.fd)

proc read*(watcher: Watcher): Future[seq[FileAction]] =
  return readEvents(watcher, 10)

# TODO:
proc close*(watcher: Watcher) =
  discard CloseHandle(HANDLE(watcher.fd))
