"""Only two bounded EP GETs; no mutation/redirect/credential fallback."""
from contextlib import contextmanager, ExitStack
import http.client
import json
import ssl
import time
from urllib.parse import urlencode
from .forge_peer import _endpoint
from .review_peer import _unique_pairs
from .concept_baseline_dispatch import install_guarded_send
from . import execution_progress_wire as wire


@contextmanager
def _authority(guard):
    # Only authority-entry failures are DENIED. Socket errors during the
    # guarded send remain availability failures, even PermissionError.
    with ExitStack() as stack:
        try:stack.enter_context(guard())
        except PermissionError:raise wire.ProgressError('DENIED',403) from None
        yield


def read(binding,mission,run=None,expected=None,*,guard=None,timeout=3):
    wire.identifier(mission)
    if run is not None:wire.identifier(run)
    if expected is not None:wire.snapshot(expected)
    selection=binding['selection'];wire.require(mission in selection['mission_ids'],'DENIED',403)
    path='/v1/execution-progress/projects/'+wire.identifier(selection['project_id'])
    if run is not None:path+='/runs/'+run
    query={'mission_id':mission}
    if expected is not None:query['expected_snapshot']=expected
    scheme,host,port=_endpoint(binding['endpoint']);timeout=min(3,max(.001,timeout));deadline=time.monotonic()+timeout
    connection=(http.client.HTTPSConnection(host,port,timeout=timeout,context=ssl.create_default_context()) if scheme=='https' else http.client.HTTPConnection(host,port,timeout=timeout))
    try:
        if guard is not None:
            with _authority(guard):pass
        connection.connect();connected_socket=connection.sock
        if guard is not None:install_guarded_send(connection,lambda:_authority(guard),max(.001,deadline-time.monotonic()))
        connection.request('GET',path+'?'+urlencode(query),headers={'Authorization':'Bearer '+binding['token'],'Accept':'application/json','EP-Progress-Contract':'1.0','EP-Instance-ID':binding['instance_id'],'EP-Consumer-ID':binding['consumer_id'],'Workspace-Instance-ID':binding['workspace_instance_id'],'EP-Audience':'workspace'})
        connected_socket.settimeout(max(.001,deadline-time.monotonic()))
        response=connection.getresponse()
        if response.status in (401,403):raise wire.ProgressError('DENIED',response.status)
        headers=response.getheaders()
        for name in ('content-type','cache-control'):
            values=[v for k,v in headers if k.lower()==name]
            wire.require(len(values)==1 and (values[0].split(';')[0].strip().lower()=='application/json' if name=='content-type' else values[0].strip().lower()=='no-store'))
        lengths=[v for k,v in headers if k.lower()=='content-length']
        wire.require(len(lengths)<=1 and (not lengths or (lengths[0].isdigit() and int(lengths[0])<=wire.MAXIMUM_BYTES)))
        raw=bytearray()
        while not response.isclosed():
            remaining=deadline-time.monotonic();wire.require(remaining>0,'UNAVAILABLE')
            connected_socket.settimeout(remaining)
            chunk=response.read1(min(65536,wire.MAXIMUM_BYTES+1-len(raw)))
            if not chunk:break
            raw.extend(chunk);wire.require(len(raw)<=wire.MAXIMUM_BYTES)
        try:value=json.loads(raw,object_pairs_hook=_unique_pairs)
        except (ValueError,UnicodeError,RecursionError):raise wire.ProgressError('INVALID_RESPONSE') from None
        if response.status!=200:wire.error(value,response.status)
        return wire.validate(value,binding,mission,run,expected)
    except (OSError,http.client.HTTPException):raise wire.ProgressError('UNAVAILABLE') from None
    finally:connection.close()
