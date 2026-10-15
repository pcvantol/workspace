"""Existing private owner pairing: exact Activity and saved project reference.

No progress state database, grant issuer, event writer or project discovery.
"""
from contextlib import contextmanager
from datetime import datetime,timezone
import fcntl
import os
import re
import secrets
from .service import _private_json,_regular_private
from .worklist_peer import WorklistReadTransport,WorklistError
from .project_links import LinkScope
from .forge_peer import _endpoint
from . import workset_activity_contract as activity_wire
from . import execution_progress_wire as wire
from .execution_progress_transport import read

FIELDS={'id','actor_id','context_id','activity_binding_id','workset_id','definition_digest','endpoint','producer_source','producer_id','selection','receipt','token','instance_id','consumer_id','workspace_instance_id','expires_at'}
CONFIG={'actor_id','context_id','activity_binding_id','workset_id','endpoint','producer_source','producer_id','selection','receipt_file','token_file'}

class ExecutionProgressPeer(WorklistReadTransport):
    def __init__(self,root,root_fd,conversations,activities,projects,instance):
        super().__init__(root,root_fd,namespace='execution-progress')
        self.conversations=conversations;self.activities=activities;self.projects=projects;self.instance=instance

    def _valid_record(self,b):
        try:
            if type(b) is not dict or set(b)!=FIELDS:return False
            for k in ('id','actor_id','context_id','activity_binding_id','workset_id','instance_id','consumer_id','workspace_instance_id','producer_id'):wire.identifier(b[k])
            _endpoint(b['endpoint']);r=b['receipt'];s=b['selection']
            if b['producer_source']!=wire.CANDIDATE_SOURCE or re.fullmatch('[A-Za-z0-9_-]{32,128}',b['token']) is None or re.fullmatch('sha256:[a-f0-9]{64}',b['definition_digest']) is None:return False
            if type(r) is not dict or set(r)!={'grant_id','instance_id','consumer_id','workspace_instance_id','audience','selections','fields','issued_at','expires_at','status'}:return False
            wire.identifier(r['grant_id'])
            if r['status']!='ACTIVE' or r['audience']!='workspace' or sorted(r['fields'])!=['history','identity','progress','result'] or b['workspace_instance_id']!=self.instance:return False
            if any(b[k]!=r[k] for k in ('instance_id','consumer_id','workspace_instance_id','expires_at')):return False
            if not wire.date(r['issued_at'])<wire.date(r['expires_at']) or (wire.date(r['expires_at'])-wire.date(r['issued_at'])).total_seconds()>86400:return False
            schema=wire.SCHEMA['oneOf'][0]['properties']['selection']
            if type(r['selections']) is not list or not 1<=len(r['selections'])<=16 or s not in r['selections']:return False
            for selection in r['selections']:
                from .advisory_contract import _check
                _check(selection,schema,{})
                for key in ('repository_ids','mission_ids','producer_ids'):
                    if not 1<=len(selection[key])<=32 or len(set(selection[key]))!=len(selection[key]):return False
            return s['producer_ids']==[b['producer_id']] and len({v['project_id'] for v in r['selections']})==len(r['selections'])
        except (KeyError,TypeError,ValueError,wire.ProgressError,WorklistError):return False

    def _bindings(self):
        try:doc=_private_json('execution-progress-bindings.json',dir_fd=self.root_fd)
        except FileNotFoundError:
            try:_private_json('execution-progress-initialized.json',dir_fd=self.root_fd)
            except FileNotFoundError:return []
            except (OSError,ValueError,UnicodeError):raise wire.ProgressError('SOURCE_CORRUPT') from None
            raise wire.ProgressError('SOURCE_CORRUPT') from None
        except (OSError,ValueError,UnicodeError):raise wire.ProgressError('SOURCE_CORRUPT') from None
        wire.require(type(doc) is dict and set(doc)=={'bindings'} and type(doc['bindings']) is list and len(doc['bindings'])<=100,'SOURCE_CORRUPT')
        rows=doc['bindings'];wire.require(all(self._valid_record(b) for b in rows),'SOURCE_CORRUPT')
        for key in (lambda b:b['id'],lambda b:(b['actor_id'],b['context_id'],b['activity_binding_id'],b['workset_id'])):
            wire.require(len({key(b) for b in rows})==len(rows),'SOURCE_CORRUPT')
        return rows

    def _write_bindings(self,rows):
        try:_private_json('execution-progress-initialized.json',dir_fd=self.root_fd)
        except FileNotFoundError:
            fd=os.open('execution-progress-initialized.json',os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600,dir_fd=self.root_fd)
            with os.fdopen(fd,'w') as stream:stream.write('{"schema_version":1}');stream.flush();os.fsync(stream.fileno())
            os.fsync(self.root_fd)
        super()._write_bindings(rows)

    def _reference(self,b):
        s=b['selection'];scope=LinkScope(b['actor_id'],b['instance_id'],frozenset([s['project_id']]),b['expires_at'],b['id'])
        wire.require(any(r['authority_id']==s['authority_repository_id'] for r in self.projects.store.identities(scope)),'UNBOUND',503)

    def _current(self,b,scope,activity):
        wire.require(b in self._bindings() and scope==(b['actor_id'],b['context_id']),'DENIED',403)
        wire.require(wire.date(b['expires_at'])>datetime.now(timezone.utc) and wire.date(activity['expires_at'])>datetime.now(timezone.utc),'DENIED',403)
        wire.require(activity in self.activities._bindings() and activity['id']==b['activity_binding_id'] and scope==(activity['actor_id'],activity['workspace_project_id']),'DENIED',403)
        wire.require({'workset_id':b['workset_id'],'definition_digest':b['definition_digest']} in activity['worksets'],'DENIED',403)
        self._reference(b)

    @contextmanager
    def guard(self,draft,activity,b):
        # Stable local-only lock order. No peer or socket operation inside.
        source=self.activities._locked()
        try:
            own=self._locked()
            try:
                scope=self.conversations.scope(draft)
                with self.conversations.forward_grant(draft,scope):
                    self._current(b,scope,activity);yield
            finally:fcntl.flock(own,fcntl.LOCK_UN);os.close(own)
        finally:fcntl.flock(source,fcntl.LOCK_UN);os.close(source)

    def _forge(self,activity,workset):
        activity_wire.capability(self.activities._request(activity),activity)
        page=self.activities.read(activity,workset)
        activity_wire.capability(self.activities._request(activity),activity)
        return {row['mission_id'] for row in page['current']['items'] if row['mission_id'] is not None}

    def binding(self,draft,activity_token,workset,expected=None):
        scope=self.conversations.scope(draft);activity=self.activities.access(activity_token)
        wire.require(scope==(activity['actor_id'],activity['workspace_project_id']),'DENIED',403)
        b=next((r for r in self._bindings() if (r['actor_id'],r['context_id'],r['activity_binding_id'],r['workset_id'])==(*scope,activity['id'],workset)),None)
        wire.require(b is not None,'UNBOUND',503)
        if expected is not None:wire.require(b['id']==expected,'DENIED',403)
        with self.guard(draft,activity,b):pass
        return activity,b

    def provision(self,config_file):
        c=_private_json(config_file);wire.require(type(c) is dict and set(c)==CONFIG,'INVALID_REQUEST',400)
        scope=(c['actor_id'],c['context_id']);wire.require(any((g['actor_id'],g['project_id'])==scope for g in self.conversations._grants()),'DENIED',403)
        activity=next((r for r in self.activities._bindings() if r['id']==c['activity_binding_id'] and (r['actor_id'],r['workspace_project_id'])==scope),None)
        wire.require(activity is not None,'DENIED',403)
        subject=next((r for r in activity['worksets'] if r['workset_id']==c['workset_id']),None);wire.require(subject is not None,'DENIED',403)
        b={k:c[k] for k in CONFIG-{'receipt_file','token_file'}};b.update(id=secrets.token_hex(16),definition_digest=subject['definition_digest'],receipt=_private_json(c['receipt_file']),token=_regular_private(c['token_file']).strip())
        b.update({k:b['receipt'][k] for k in ('instance_id','consumer_id','workspace_instance_id','expires_at')});wire.require(self._valid_record(b),'INVALID_REQUEST',400);self._reference(b)
        wire.require(wire.date(b['expires_at'])>datetime.now(timezone.utc),'DENIED',403)
        missions=self._forge(activity,b['workset_id']);wire.require(set(b['selection']['mission_ids'])<=missions,'DENIED',403)
        for mission in b['selection']['mission_ids']:read(b,mission)
        source=self.activities._locked()
        try:
            own=self._locked()
            try:
                wire.require(activity in self.activities._bindings(),'DENIED',403)
                rows=self._bindings();wire.require(len(rows)<100 and not any((r['actor_id'],r['context_id'],r['activity_binding_id'],r['workset_id'])==(*scope,activity['id'],b['workset_id']) for r in rows),'BINDING_CONFLICT',409)
                self._write_bindings([*rows,b])
            finally:fcntl.flock(own,fcntl.LOCK_UN);os.close(own)
        finally:fcntl.flock(source,fcntl.LOCK_UN);os.close(source)
        return {'binding_id':b['id'],'workset_id':b['workset_id'],'producer_source':b['producer_source']}

    def fetch(self,draft,activity_token,workset,mission,run=None,expected=None,binding_id=None):
        activity,b=self.binding(draft,activity_token,workset,binding_id)
        with self.guard(draft,activity,b):wire.require(mission in b['selection']['mission_ids'],'DENIED',403)
        wire.require(mission in self._forge(activity,workset),'DENIED',403)
        packet=read(b,mission,run,expected,guard=lambda:self.guard(draft,activity,b))
        with self.guard(draft,activity,b):pass
        expiry=min(wire.date(b['expires_at']),wire.date(activity['expires_at'])).isoformat()
        envelope={'contract_version':'workspace-execution-progress/1','actor_id':b['actor_id'],'context_id':b['context_id'],'workspace_instance_id':self.instance,'binding_id':b['id'],'activity_binding_id':activity['id'],'forge_instance_id':activity['forge_instance_id'],'workset_id':workset,'producer_source':b['producer_source'],'expires_at':expiry,'packet':packet}
        return envelope,ExecutionPublication(self,draft,activity,b,mission,run,packet['snapshot_id'])

class ExecutionPublication:
    def __init__(self,peer,draft,activity,binding,mission,run,snapshot):
        self.peer=peer;self.draft=draft;self.activity=activity;self.binding=binding;self.mission=mission;self.run=run;self.snapshot=snapshot
    def dispatch_guard(self,draft,identity,binding):
        wire.require((draft,identity,binding)==(self.draft,self.binding['workset_id'],self.binding),'DENIED',403)
        return self.peer.guard(draft,self.activity,binding)
    def cap(self,binding,*,timeout=3,send_guard=None):
        wire.require(binding==self.binding,'DENIED',403)
        # Existing GET is the only supported EP access/snapshot recheck.
        wire.require(self.mission in self.peer._forge(self.activity,binding['workset_id']),'DENIED',403)
        return read(binding,self.mission,self.run,self.snapshot,guard=send_guard,timeout=timeout)
