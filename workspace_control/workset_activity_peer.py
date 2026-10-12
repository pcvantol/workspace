"""Finite READ-only activity binding. Existing mutation pins and grants stay separate."""
from contextlib import contextmanager
import os
import re
from .advisory_http import request
from .forge_peer import _endpoint
from .service import _private_json, _regular_private
from .review_peer import _id
from .worklist_peer import WorklistReadTransport, WorklistError, _FORGE_TOKEN
from . import workset_activity_contract as wire


class WorksetActivityTransport(WorklistReadTransport):
    scope_field='worksets'
    def __init__(self,root,root_fd):super().__init__(root,root_fd,namespace='workset-activity')

    def _valid_record(self,v):
        keys={'id','client_digest','actor_id','workspace_project_id','endpoint','forge_token','forge_instance_id','forge_project_id','repository_id','installation_id','worksets','expires_at','producer_source'}
        if not isinstance(v,dict) or set(v)!=keys:return False
        if not all(_id(v[k]) for k in ['id','actor_id','workspace_project_id','forge_instance_id','forge_project_id','repository_id','installation_id']):return False
        if not isinstance(v['client_digest'],str) or not isinstance(v['forge_token'],str) or re.fullmatch('[0-9a-f]{64}',v['client_digest']) is None or _FORGE_TOKEN.fullmatch(v['forge_token']) is None or v['producer_source']!=wire.PIN:return False
        try:
            _endpoint(v['endpoint'])
            _check_subjects(v['worksets'])
            if not isinstance(v['expires_at'],str):return False
            from datetime import datetime
            if datetime.fromisoformat(v['expires_at'].replace('Z','+00:00')).utcoffset() is None:return False
        except (ValueError,WorklistError):return False
        return True

    def provision(self,actor,project,endpoint,receipt_file,forge_token_file,client_token_file):
        if not _id(actor) or not _id(project):raise ValueError('invalid own actor/context')
        _endpoint(endpoint)
        if not all(os.path.isabs(p) for p in [receipt_file,forge_token_file,client_token_file]):raise ValueError('private absolute paths required')
        import json
        receipt=json.loads(_regular_private(receipt_file));token=_regular_private(forge_token_file).strip()
        wire.require(receipt['permissions']==['READ'] and receipt['state']=='ACTIVE' and receipt['principal_id']==actor,'DENIED')
        binding={'actor_id':actor,'workspace_project_id':project,'endpoint':endpoint,'forge_token':token,'forge_instance_id':receipt['instance_id'],'forge_project_id':receipt['project_id'],'repository_id':receipt['repository_id'],'installation_id':receipt['installation_id'],'worksets':receipt['worksets'],'expires_at':receipt['expires_at'],'producer_source':wire.PIN}
        wire.require(self._valid_record({'id':'probe','client_digest':'0'*64,**binding}))
        wire.capability(self._request(binding),binding)
        for subject in binding['worksets']:
            self.read(binding,subject['workset_id'])
        wire.capability(self._request(binding),binding)
        return self._provision_binding(binding,client_token_file)

    def _request(self,binding,suffix=''):
        return request(binding,'GET',wire.BASE+suffix,error_validator=wire.validate,maximum_bytes=32768,missing_as_state='UNSUPPORTED' if not suffix else None)

    @contextmanager
    def gate(self,binding,scope):
        descriptor=self._locked()
        try:
            wire.require(binding in self._bindings() and scope==(binding['actor_id'],binding['workspace_project_id']),'DENIED')
            cap=wire.capability(self._request(binding),binding)
            yield cap
        finally:os.close(descriptor)

    def metadata(self,binding,cap):
        return {'consumer_contract':'workspace-workset-activity-access/v1','binding_id':binding['id'],'actor_id':binding['actor_id'],'workspace_project_id':binding['workspace_project_id'],'producer_source':wire.PIN,'producer_version':'2.15.0','installation_id':binding['installation_id'],**cap}

    def read(self,binding,workset,cursor=None,event=None):
        wire.require(_id(workset) and any(w['workset_id']==workset for w in binding['worksets']),'DENIED')
        suffix='/'+workset+'/pages'
        if cursor is not None:
            wire.require(isinstance(cursor,str) and cursor not in ('.','..') and re.fullmatch('[A-Za-z0-9_.-]{1,32768}',cursor) is not None,'INVALID_REQUEST');suffix+='/'+cursor
        if event is not None:
            wire.require(re.fullmatch('[0-9a-f]{64}',event) is not None,'INVALID_REQUEST');suffix='/'+workset+'/events/'+event
        result=self._request(binding,suffix)
        return wire.read(result,'detail' if event else 'page',binding,workset,event)


def _check_subjects(values):
    wire.require(isinstance(values,list) and 1<=len(values)<=16)
    wire.require(all(isinstance(v,dict) and set(v)=={'workset_id','definition_digest'} and _id(v['workset_id']) and isinstance(v['definition_digest'],str) and re.fullmatch('sha256:[0-9a-f]{64}',v['definition_digest']) for v in values))
    wire.require(len({v['workset_id'] for v in values})==len(values))
