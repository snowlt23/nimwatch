
import posix
import types

type FD* = cint
type WD* = cint

{.pragma: importinotify, cdecl, importc, header: "sys/inotify.h".}

const IN_MODIFY* = 0x00000002
const IN_ATTRIB* = 0x00000004
const IN_MOVED_FROM* = 0x00000040
const IN_MOVED_TO* = 0x00000080
const IN_CREATE* = 0x00000100
const IN_DELETE* = 0x00000200

const DefaultEvents* = IN_MODIFY or IN_MOVED_FROM or IN_MOVED_TO or IN_CREATE or IN_DELETE

type
  FileNameArray* {.unchecked.} = array[0..0, char]
  InotifyEvent* = object
    wd*: WD
    mask*: uint32
    cookie*: uint32
    len*: uint32
    name*: FileNameArray

let EventSize* = sizeof(InotifyEvent)
let BufLen* = 1024 * (EventSize + 16)

proc inotify_init*(): FD {.importinotify.}
proc inotify_add_watch*(fd: FD, target: cstring, events: cint): WD {.importinotify.}
proc inotify_rm_watch*(fd: FD, wd: WD) {.importinotify.}

proc readEvents*(fd: FD): seq[FileAction] =
  result = @[]

  var buffer = newString(BufLen)
  let length = read(fd, buffer[0].addr, BufLen)
  if length < 0:
    return

  var i = 0
  while i < length:
    var action: FileAction
    let event = cast[ptr InotifyEvent](buffer[i].addr)
    if (event[].mask and IN_MODIFY) != 0:
      action.kind = actionModify
    elif (event[].mask and IN_MOVED_FROM) != 0:
      action.kind = actionMoveFrom
    elif (event[].mask and IN_MOVED_TO) != 0:
      action.kind = actionMoveTo
    elif (event[].mask and IN_DELETE) != 0:
      action.kind = actionDelete
    elif (event[].mask and IN_CREATE) != 0:
      action.kind = actionCreate

    action.filename = $event[].name
    result.add(action)
    
    i += EventSize + event[].len.int

#
# Watcher
#

proc init*(watcher: Watcher) =
  watcher.fd = inotify_init()
  watcher.wd = inotify_add_watch(watcher.fd, target, DefaultEvents)

proc wait*(watcher: Watcher): seq[FileAction] =
  return readEvents(watcher.fd)

proc close*(watcher: Watcher) =
  inotify_rm_watch(watcher.fd, watcher.wd)
  close(watcher.fd)
  