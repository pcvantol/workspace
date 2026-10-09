"""Private owner-attested advisory binding; existing Workspace conversations remain local."""
import os
import json
import re
from urllib.parse import urlencode
from hashlib import sha256
from .worklist_peer import WorklistReadTransport, WorklistError, _ids, _FORGE_TOKEN
from .advisory_http import request as control_request
from contextlib import contextmanager, nullcontext
from .service import _regular_private
from .review_peer import _id, _time
from .forge_peer import _endpoint
from . import advisory_contract as wire

class AdvisoryTransport(WorklistReadTransport):
    scope_field='conversation_ids'
    wire=wire
    prefix='/v1/advisory'
    binding_namespace='advisory'
    def __init__(self,root,root_fd,conversations):
        super().__init__(root,root_fd,namespace=self.binding_namespace);self.conversations=conversations

    def _valid_record(self,b):
        fields={'id','client_digest','actor_id','endpoint','forge_instance_id','forge_token','conversation_ids',
                'workspace_project_id','forge_project_id','repository_id','grant_id'}
        if not isinstance(b,dict) or set(b)!=fields:return False
        if not all(_id(b[k]) for k in ['id','actor_id','forge_instance_id','workspace_project_id','forge_project_id','repository_id','grant_id']):return False
        if not isinstance(b['client_digest'],str) or not isinstance(b['forge_token'],str) or re.fullmatch('[0-9a-f]{64}',b['client_digest']) is None or _FORGE_TOKEN.fullmatch(b['forge_token']) is None or not _ids(b['conversation_ids'],16):return False
        try:_endpoint(b['endpoint'])
        except ValueError:return False
        return self._valid_conversations(b['conversation_ids'])

    def _valid_conversations(self,values):
        return all(re.fullmatch('[0-9a-f]{32}',c) for c in values)

    def _local_conversations(self,b,values):
        for c in values:self.conversations.get((b['actor_id'],b['workspace_project_id']),c)

    def provision(self,actor,workspace_project,endpoint,receipt_file,forge_token_file,client_token_file):
        if not _id(actor) or not _id(workspace_project):raise ValueError('invalid advisory binding')
        _endpoint(endpoint)
        if not all(isinstance(p,str) and os.path.isabs(p) for p in [receipt_file,forge_token_file,client_token_file]):raise ValueError('private absolute paths required')
        token=_regular_private(forge_token_file).strip();proof=json.loads(_regular_private(receipt_file))
        # The producer capability does not publish its principal. Require the trusted
        # owner issuance receipt paired to the actual private token at setup, never actor JSON from the client.
        fields={'instance_id','project_id','repository_id','principal_id','conversation_ids',
                'grant_id','maximum_turns','expires_at','state','token_sha256'}
        if not isinstance(proof,dict) or set(proof)!=fields or proof['principal_id']!=actor or proof['state']!='ACTIVE' or not _time(proof['expires_at']) or type(proof['maximum_turns']) is not int or not 1<=proof['maximum_turns']<=8:raise ValueError('invalid owner issuance proof')
        if _FORGE_TOKEN.fullmatch(token) is None or proof['token_sha256']!=sha256(token.encode('ascii')).hexdigest():raise ValueError('owner receipt/token mismatch')
        b={'actor_id':actor,'workspace_project_id':workspace_project,'endpoint':endpoint,'forge_instance_id':proof['instance_id'],
           'forge_project_id':proof['project_id'],'repository_id':proof['repository_id'],'grant_id':proof['grant_id'],
           'forge_token':token,'conversation_ids':proof['conversation_ids']}
        if not self._valid_record({'id':'probe','client_digest':'0'*64,**b}):raise ValueError('invalid scope')
        self._local_conversations(b,b['conversation_ids'])
        self.capability(b,[])
        result=self._provision_binding(b,client_token_file);return {**result,'workspace_project_id':workspace_project,'forge_project_id':b['forge_project_id'],'repository_id':b['repository_id']}

    def bound(self,b,scope,conversation=None):
        if scope!=(b['actor_id'],b['workspace_project_id']):raise WorklistError('DENIED')
        if conversation is not None:
            if conversation not in b['conversation_ids']:raise WorklistError('DENIED')
            self._local_conversations(b,[conversation])

    def metadata(self,b,scope):
        self.bound(b,scope);self.capability(b,[])
        return {'contract_version':'workspace-advisory-access/v1','actor_id':b['actor_id'],
                'workspace_project_id':b['workspace_project_id'],'instance_id':b['forge_instance_id'],
                'project_id':b['forge_project_id'],'repository_id':b['repository_id'],'conversation_ids':b['conversation_ids']}

    def capability(self,b,selections):
        if not isinstance(selections,list) or len(selections)>2:raise WorklistError('INVALID_REQUEST')
        for s in selections:self.wire.validate(s,'source')
        query=urlencode([pair for s in selections for pair in [('source_id',s['source_id']),('source_version',s['version'])]])
        return self.wire.response(self._read(b,self.prefix+'/capability'+('?' + query if query else '')),'capability',b)

    def history(self,b,c,cursor,limit):
        if type(cursor) is not int or not 0<=cursor<=8 or type(limit) is not int or not 1<=limit<=4:raise WorklistError('INVALID_REQUEST')
        return self.wire.response(self._read(b,f'{self.prefix}/{c}?cursor={cursor}&limit={limit}'),'history',b,c)

    def turn(self,b,c,t):
        if not _id(t):raise WorklistError('INVALID_REQUEST')
        v=self.wire.response(self._read(b,f'{self.prefix}/{c}/turns/{t}'),'turn',b,c)
        if v['original_turn']['request']['turn_id']!=t:raise WorklistError('INVALID_RESPONSE')
        return v

    def submit(self,b,c,body,*,authority):
        self.wire.request(body,b,c)
        return self._write(b,f'{self.prefix}/{c}/turns',body,'submit',c,body,authority=authority)

    def cancel(self,b,c,t,body,*,authority):
        if not _id(t):raise WorklistError('INVALID_REQUEST')
        try:self.wire.validate(body,'cancel_request')
        except WorklistError:raise WorklistError('INVALID_REQUEST') from None
        v=self._write(b,f'{self.prefix}/{c}/turns/{t}/cancel',body,'cancel',c,authority=authority)
        if v['original_turn']['request']['turn_id']!=t or v['original_turn']['request_digest']!=body['request_digest']:raise WorklistError('INVALID_RESPONSE')
        return v

    @contextmanager
    def _forward_gate(self,b,authority=None):
        fd=self._locked()
        try:
            with authority or nullcontext():
                if b not in self._bindings():raise WorklistError('DENIED')
                yield
        except PermissionError:raise WorklistError('DENIED') from None
        finally:os.close(fd)

    def _write(self,b,path,body,kind,c,expected=None,*,authority):
        raw=control_request(b,'POST',path,body,gate=self._forward_gate(b,authority),error_validator=self.wire.validate)
        if b not in self._bindings():raise WorklistError('DENIED')
        return self.wire.response(raw,kind,b,c,expected)

    def _read(self,b,path):
        # Provision probes are owner-attested but not yet registered. Every
        # registered binding is fenced both when forwarding and after waiting.
        registered='client_digest' in b
        raw=control_request(b,'GET',path,gate=self._forward_gate(b) if registered else None,error_validator=self.wire.validate)
        if registered and b not in self._bindings():raise WorklistError('DENIED')
        return raw
