"""Separate owner-issued Candidate transport; Forge owns proposals and registration."""
import json
import os
from hashlib import sha256
from .advisory_peer import AdvisoryTransport
from .advisory_http import request as control_request
from .worklist_peer import WorklistReadTransport, WorklistError, _FORGE_TOKEN, _ids
from .service import _regular_private
from .review_peer import _id, _time
from .forge_peer import _endpoint
from . import candidate_contract as wire

class CandidateTransport(AdvisoryTransport):
    def __init__(self,root,root_fd,conversations):
        WorklistReadTransport.__init__(self,root,root_fd,namespace='candidate')
        self.conversations=conversations

    def _valid_record(self,b):
        if not isinstance(b,dict) or not {'conversation_id','proposal_ids','maximum_registrations'}<=set(b):return False
        legacy={k:v for k,v in b.items() if k not in ('conversation_id','proposal_ids','maximum_registrations')}
        return (super()._valid_record(legacy) and legacy['conversation_ids']==[b['conversation_id']] and
                _ids(b['proposal_ids'],16) and b['proposal_ids']==sorted(b['proposal_ids']) and
                type(b['maximum_registrations']) is int and 1<=b['maximum_registrations']<=8)

    def provision(self,actor,workspace_project,endpoint,receipt_file,forge_token_file,client_token_file):
        if not _id(actor) or not _id(workspace_project):raise ValueError('invalid Candidate binding')
        _endpoint(endpoint)
        if not all(isinstance(p,str) and os.path.isabs(p) for p in [receipt_file,forge_token_file,client_token_file]):raise ValueError('private absolute paths required')
        token=_regular_private(forge_token_file).strip();proof=json.loads(_regular_private(receipt_file))
        names=set('instance_id project_id repository_id principal_id conversation_id proposal_ids grant_id maximum_registrations expires_at state token_sha256'.split())
        if not isinstance(proof,dict) or set(proof)!=names or proof['principal_id']!=actor or proof['state']!='ACTIVE' or not _time(proof['expires_at']):raise ValueError('invalid owner Candidate issuance proof')
        if _FORGE_TOKEN.fullmatch(token) is None or proof['token_sha256']!=sha256(token.encode('ascii')).hexdigest():raise ValueError('owner receipt/token mismatch')
        b={'actor_id':actor,'workspace_project_id':workspace_project,'endpoint':endpoint,'forge_instance_id':proof['instance_id'],
           'forge_project_id':proof['project_id'],'repository_id':proof['repository_id'],'grant_id':proof['grant_id'],
           'forge_token':token,'conversation_id':proof['conversation_id'],'conversation_ids':[proof['conversation_id']],
           'proposal_ids':proof['proposal_ids'],'maximum_registrations':proof['maximum_registrations']}
        if not self._valid_record({'id':'probe','client_digest':'0'*64,**b}):raise ValueError('invalid Candidate scope')
        self.conversations.get((actor,workspace_project),b['conversation_id'])
        self.capability(b)
        result=self._provision_binding(b,client_token_file)
        return {**result,'workspace_project_id':workspace_project,'forge_project_id':b['forge_project_id'],'repository_id':b['repository_id'],'conversation_id':b['conversation_id'],'proposal_ids':b['proposal_ids'],'maximum_registrations':b['maximum_registrations']}

    def metadata(self,b,scope):
        self.bound(b,scope);self.capability(b)
        return {'contract_version':'workspace-candidate-access/v1','actor_id':b['actor_id'],'workspace_project_id':b['workspace_project_id'],
                'instance_id':b['forge_instance_id'],'project_id':b['forge_project_id'],'repository_id':b['repository_id'],
                'conversation_id':b['conversation_id'],'proposal_ids':b['proposal_ids'],'maximum_registrations':b['maximum_registrations']}

    def _current_authority(self,b,raw=None):
        if b not in self._bindings():raise WorklistError('DENIED')
        wire.response(control_request(b,'GET','/v1/advisory-candidates/capability',gate=self._forward_gate(b),error_validator=wire.validate),'capability',b)
        # A delayed historical response cannot retain a source whose ACL was
        # revoked while the response was in flight. Re-read the exact source,
        # never substitute newer metadata or call a provider.
        if raw is not None:
            if not isinstance(raw,dict) or any(k in raw and not isinstance(raw[k],dict) for k in ('proposal','original_receipt')):raise WorklistError('INVALID_RESPONSE')
            original=raw.get('source') or raw.get('proposal',{}).get('source') or raw.get('original_receipt',{}).get('source')
            if original is not None:
                wire.source(original)
                path=f"/v1/advisory-candidates/{b['conversation_id']}/source/{original['turn_id']}"
                wire.response(control_request(b,'GET',path,gate=self._forward_gate(b),error_validator=wire.validate),'source_read',b,b['conversation_id'],original['turn_id'])
        if b not in self._bindings():raise WorklistError('DENIED')

    def _read(self,b,path):
        registered='client_digest' in b
        raw=control_request(b,'GET',path,gate=self._forward_gate(b) if registered else None,error_validator=wire.validate)
        if registered:self._current_authority(b,raw)
        return raw

    def capability(self,b):
        return wire.response(self._read(b,'/v1/advisory-candidates/capability'),'capability',b)

    def source(self,b,c,t):
        if not _id(t):raise WorklistError('INVALID_REQUEST')
        return wire.response(self._read(b,f'/v1/advisory-candidates/{c}/source/{t}'),'source_read',b,c,t)

    def preview(self,b,c,p,revision):
        if p not in b['proposal_ids']:raise WorklistError('DENIED')
        if type(revision) is not int or not 1<=revision<=8:raise WorklistError('INVALID_REQUEST')
        return wire.response(self._read(b,f'/v1/advisory-candidates/{c}/proposals/{p}?revision={revision}'),'preview',b,c,p,revision)

    def operation(self,b,c,p,o):
        if p not in b['proposal_ids']:raise WorklistError('DENIED')
        if not _id(o):raise WorklistError('INVALID_REQUEST')
        raw=self._read(b,f'/v1/advisory-candidates/{c}/proposals/{p}/registrations/{o}')
        value=wire.response(raw,'pending' if raw.get('state')=='PENDING' else 'registration',b,c,p,expected=o if raw.get('state')=='PENDING' else None)
        if raw.get('state')!='PENDING':wire.correlate(value,self.preview(b,c,p,value['original_receipt']['proposal_revision'])['proposal'])
        return value

    def command(self,b,c,body,*,registration=False,authority):
        kind='registration_request' if registration else 'proposal_request'
        wire.request(body,kind,b,c)
        path=f'/v1/advisory-candidates/{c}/proposals'+(f"/{body['proposal_id']}/registrations" if registration else '')
        raw=control_request(b,'POST',path,body,gate=self._forward_gate(b,authority),error_validator=wire.validate)
        self._current_authority(b,raw)
        value=wire.response(raw,'registration' if registration else 'saved',b,c,body['proposal_id'],None if registration else body['expected_revision']+1,body)
        if registration:wire.correlate(value,self.preview(b,c,body['proposal_id'],body['proposal_revision'])['proposal'])
        return value
