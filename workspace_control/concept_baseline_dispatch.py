"""Short current-authority fences around nonblocking proposal request sends."""
import select
import ssl
import time
from .worklist_peer import WorklistError


def install_guarded_send(connection, guard, timeout):
    socket=connection.sock
    def send(data):
        deadline=time.monotonic()+timeout
        old_timeout=socket.gettimeout();socket.setblocking(False)
        try:
            offset=0;wait_read=False
            while offset<len(data):
                remaining=deadline-time.monotonic()
                if remaining<=0:raise WorklistError('UNAVAILABLE')
                readable,writable,_=select.select([socket] if wait_read else [],[] if wait_read else [socket],[],min(.1,remaining))
                if not (readable or writable):continue
                # Guard factory rechecks current own concept and original pairing
                # per chunk; network backpressure and computation wait are outside.
                with guard():
                    try:count=socket.send(data[offset:offset+65536])
                    except ssl.SSLWantReadError:wait_read=True;continue
                    except (BlockingIOError,ssl.SSLWantWriteError):wait_read=False;continue
                    if count<=0:raise WorklistError('UNAVAILABLE')
                    offset+=count;wait_read=False
        finally:socket.settimeout(old_timeout)
    connection.send=send
