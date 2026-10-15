"""Qualified HOB-EP01 HTTP consumer. No producer source or token issuer.

Trusted local owner pairs one existing actor/context to a narrower finite EP
READ receipt. Product requests contain neither endpoint nor upstream credential.
"""
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import http.client
import json
import os
from pathlib import Path
import re
import secrets
import ssl
from urllib.parse import urlencode
from .advisory_contract import _check
from .forge_peer import _endpoint
from .project_links import LinkScope, LinkConflict, ProducerUnavailable, identifier, timestamp
from .review_peer import _unique_pairs
from .service import _private_json, _regular_private
from .worklist_peer import WorklistReadTransport, WorklistError

SOURCE='f375a4e8adcec0c1693aa100c0f31f6014b84b20'
SCHEMA=json.loads(Path(__file__).with_name('project-discovery-v1.json').read_text())
FIELDS={'id','actor_id','context_id','endpoint','token','receipt','project_ids','producer_source'}


def ep_get(binding,path):
    scheme,host,port=_endpoint(binding['endpoint'])
    connection=(http.client.HTTPSConnection(host,port,timeout=10,context=ssl.create_default_context()) if scheme=='https' else http.client.HTTPConnection(host,port,timeout=10))
    receipt=binding['receipt']
    try:
        connection.request('GET',path,headers={'Authorization':'Bearer '+binding['token'],'Accept':'application/json','EP-Discovery-Contract':'1.0','EP-Instance-ID':receipt['instance_id'],'EP-Consumer-ID':receipt['consumer_id'],'Workspace-Instance-ID':receipt['workspace_instance_id'],'EP-Audience':'workspace'})
        response=connection.getresponse()
        if response.status in (401,403):raise PermissionError('EP read denied')
        if response.status==409:raise LinkConflict('EP snapshot changed')
        if response.status==422:raise ProducerUnavailable('EP contract unavailable')
        if response.status!=200:raise ConnectionError('EP read unavailable')
        if response.getheader('Content-Type','').split(';')[0].lower()!='application/json' or response.getheader('Cache-Control','').lower()!='no-store':raise ValueError('invalid EP content')
        raw=response.read(262145)
        if len(raw)>262144:raise ValueError('EP response limit')
        return json.loads(raw,object_pairs_hook=_unique_pairs)
    except (PermissionError,ProducerUnavailable):raise
    except (OSError,http.client.HTTPException):raise ConnectionError('EP read unavailable') from None
    finally:connection.close()


class ProjectLinkPeer(WorklistReadTransport):
    def __init__(self,root,root_fd,conversations,instance):
        super().__init__(root,root_fd,namespace='project-link');self.conversations=conversations;self.instance=instance

    def _validate(self,b):
        if type(b) is not dict or set(b)!=FIELDS or b['producer_source']!=SOURCE:raise ValueError('invalid EP pairing')
        for k in ('id','actor_id','context_id'):identifier(b[k])
        _endpoint(b['endpoint'])
        if not isinstance(b['token'],str) or re.fullmatch('[A-Za-z0-9_-]{32,256}',b['token']) is None:raise ValueError('invalid EP credential')
        try:_check(b['receipt'],SCHEMA['$defs']['ReadScope'],SCHEMA['$defs'])
        except WorklistError:raise ValueError('invalid EP receipt') from None
        rec=b['receipt']
        if rec['workspace_instance_id']!=self.instance or rec['audience']!='workspace' or not {'project_identity','repository_identity'}<=set(rec['fields']):raise PermissionError('EP receipt binding denied')
        if len(rec['fields'])!=len(set(rec['fields'])) or len(rec['project_ids'])!=len(set(rec['project_ids'])):raise ValueError('duplicate EP scope')
        ids=b['project_ids']
        if type(ids) is not list or len(ids)>100 or len(set(ids))!=len(ids) or not set(ids)<=set(rec['project_ids']):raise PermissionError('EP viewer bounds denied')
        for identity in ids:identifier(identity)
        if timestamp(rec['issued_at'])>=timestamp(rec['expires_at']):raise ValueError('invalid EP lifetime')
        return b

    def _bindings(self):
        try:doc=_private_json('project-link-bindings.json',dir_fd=self.root_fd)
        except FileNotFoundError:
            try:_private_json('project-link-bindings-initialized.json',dir_fd=self.root_fd)
            except FileNotFoundError:return []
            raise ValueError('lost EP pairing store') from None
        if type(doc) is not dict or set(doc)!={'bindings'} or type(doc['bindings']) is not list or len(doc['bindings'])>100:raise ValueError('invalid EP pairing store')
        rows=[self._validate(b) for b in doc['bindings']]
        if len({b['id'] for b in rows})!=len(rows) or len({(b['actor_id'],b['context_id']) for b in rows})!=len(rows):raise ValueError('duplicate EP pairing')
        return rows

    def _write_bindings(self,rows):
        try:_private_json('project-link-bindings-initialized.json',dir_fd=self.root_fd)
        except FileNotFoundError:
            fd=os.open('project-link-bindings-initialized.json',os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600,dir_fd=self.root_fd)
            with os.fdopen(fd,'w') as stream:stream.write('{"schema_version":1}');stream.flush();os.fsync(stream.fileno())
            os.fsync(self.root_fd)
        super()._write_bindings(rows)

    def _binding(self,actor,context):
        row=next((b for b in self._bindings() if (b['actor_id'],b['context_id'])==(actor,context)),None)
        if row is None:raise ProducerUnavailable('EP pairing not configured')
        return row

    def scope(self,token):
        actor,context=self.conversations.scope(token);b=self._binding(actor,context);rec=b['receipt']
        scope=LinkScope(actor,rec['instance_id'],frozenset(b['project_ids']),rec['expires_at'],b['id'])
        scope.require();return scope

    def _for_scope(self,scope):
        b=next((b for b in self._bindings() if b['id']==scope.epoch),None)
        if b is None or b['actor_id']!=scope.actor_id:raise PermissionError('EP pairing revoked')
        rec=b['receipt']
        if (rec['instance_id'],frozenset(b['project_ids']),rec['expires_at'])!=(scope.peer_id,scope.project_ids,scope.expires_at):raise PermissionError('EP scope changed')
        scope.require();return b

    @contextmanager
    def authorization(self,token,expected):
        fd=self._locked()
        try:
            original=self.conversations.scope(token)
            with self.conversations.forward_grant(token,original):
                if self.scope(token)!=expected:raise PermissionError('current link scope changed')
                yield
                if self.scope(token)!=expected:raise PermissionError('current link scope changed')
        finally:fcntl.flock(fd,fcntl.LOCK_UN);os.close(fd)

    def provision(self,actor,context,endpoint,source,receipt_file,token_file,project_ids):
        # Existing owning actor context must already be explicitly paired.
        if not any((g['actor_id'],g['project_id'])==(actor,context) for g in self.conversations._grants()):raise PermissionError('own actor pairing required')
        receipt=_private_json(receipt_file);token=_regular_private(token_file).strip()
        b=self._validate({'id':secrets.token_hex(16),'actor_id':actor,'context_id':context,'endpoint':endpoint,'token':token,'receipt':receipt,'project_ids':project_ids,'producer_source':source})
        scope=LinkScope(actor,receipt['instance_id'],frozenset(project_ids),receipt['expires_at'],b['id']);scope.require()
        self._pages(b)  # Real finite EP read admission before local installation.
        fd=self._locked()
        try:
            rows=self._bindings()
            if len(rows)>=100 or any((v['actor_id'],v['context_id'])==(actor,context) for v in rows):raise LinkConflict('EP pairing already exists')
            self._write_bindings([*rows,b])
        finally:fcntl.flock(fd,fcntl.LOCK_UN);os.close(fd)
        return {'binding_id':b['id'],'state':'ACTIVE','producer_source':source}

    def revoke(self,identity):
        fd=self._locked()
        try:
            rows=self._bindings();remaining=[b for b in rows if b['id']!=identity]
            if len(rows)==len(remaining):raise FileNotFoundError('EP pairing not found')
            self._write_bindings(remaining)
        finally:fcntl.flock(fd,fcntl.LOCK_UN);os.close(fd)
        return {'binding_id':identity,'state':'REVOKED'}

    def _read(self,b,path,kind):
        value=ep_get(b,path)
        try:_check(value,SCHEMA['$defs'][kind],SCHEMA['$defs'])
        except WorklistError:raise ValueError('invalid EP schema') from None
        if value['producer']!={'id':'engineering-platform','version':'2.3.120'} or value['instance_id']!=b['receipt']['instance_id'] or value['scope']!=b['receipt']:raise PermissionError('EP producer or scope mismatch')
        if value['snapshot_id']!=value['topology_revision']:raise ValueError('EP snapshot mismatch')
        if timestamp(value['observed_at'])>datetime.now(timezone.utc):raise ValueError('future EP observation')
        return value

    def _pages(self,b):
        rows=[];seen=set();cursor=None;revision=None
        for _ in range(5):
            query={'limit':25}
            if cursor is not None:query['cursor']=cursor
            value=self._read(b,'/v1/onboarding/projects?'+urlencode(query),'DiscoverySnapshot')
            if revision is not None and revision!=value['topology_revision']:raise LinkConflict('EP pages changed')
            revision=value['topology_revision']
            for row in value['projects']:
                if row['project_id'] in seen or row['project_id'] not in b['receipt']['project_ids']:raise ValueError('invalid EP project scope')
                seen.add(row['project_id']);rows.append(row)
            if len(rows)>100:raise ValueError('EP project limit')
            next_cursor=value['next_cursor']
            if next_cursor is None:
                if value['completeness']!='COMPLETE_PAGE':raise ValueError('incomplete EP page')
                return rows,revision
            if value['completeness']!='PARTIAL_PAGE' or not next_cursor or next_cursor==cursor:raise ValueError('invalid EP cursor')
            cursor=next_cursor
        raise ValueError('EP pagination limit')

    def discover(self,scope):
        b=self._for_scope(scope);rows,_=self._pages(b);self._for_scope(scope)
        # Producer supplies canonical identity, no display-name fact. Display it
        # honestly rather than deriving a name from a URL/path or inventing one.
        return [{'id':v['project_id'],'name':v['project_id']} for v in rows if v['project_id'] in scope.project_ids]

    def topology(self,scope,project):
        scope.require(project);b=self._for_scope(scope);rows,revision=self._pages(b)
        row=next((v for v in rows if v['project_id']==project),None)
        if row is None:raise PermissionError('EP project not available')
        value=self._read(b,'/v1/onboarding/projects/'+project+'/topology?'+urlencode({'expected_topology_revision':revision}),'TopologySnapshot')
        if value['project']!=row or value['topology_revision']!=revision:raise LinkConflict('EP selected topology changed')
        repos=value['repositories'];ids=[v['repository_id'] for v in repos]
        if len(set(ids))!=len(ids) or [v['repository_id'] for v in repos if v['role']=='authority']!=[row['authority_repository_id']]:raise ValueError('invalid EP authority')
        attachments=value['attachments'];granted='attachment_availability' in b['receipt']['fields']
        if (value['attachment_visibility']=='GRANTED')!=granted or (attachments is None)==granted:raise ValueError('invalid EP attachment visibility')
        if attachments is not None:
            keys=[(v['repository_id'],v['agent_id']) for v in attachments]
            if len(set(keys))!=len(keys) or any(v['repository_id'] not in ids for v in attachments):raise ValueError('invalid EP attachments')
        self._for_scope(scope)
        return {'peer_id':scope.peer_id,'project_id':project,'name':project,'authority_repository_id':row['authority_repository_id'],'revision':revision,'observed_at':value['observed_at'],'repositories':[{'id':v['repository_id'],'name':v['repository_id'],'role':v['role'],'available_attachments':None if attachments is None else sum(a['repository_id']==v['repository_id'] and a['availability']=='AVAILABLE' for a in attachments)} for v in repos]}
