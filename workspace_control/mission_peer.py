"""Concept HTTP through existing scoped advisory transport; no approval planner."""
from urllib.parse import urlencode
import re
from .advisory_peer import AdvisoryTransport
from .advisory_http import request as control_request
from .worklist_peer import WorklistError
from . import mission_contract as wire


class MissionConceptTransport(AdvisoryTransport):
    wire = wire
    prefix = '/v1/mission-concepts'

    def _read(self, binding, path):
        value = super()._read(binding, path)
        if 'client_digest' in binding:
            # Fence a delayed body against present producer grant authority too.
            current = control_request(binding, 'GET', self.prefix+'/capability', gate=self._forward_gate(binding), error_validator=wire.validate)
            wire.response(current, 'capability', binding)
            if binding not in self._bindings():
                raise WorklistError('DENIED')
        return value

    def _source_authority(self, binding, record):
        selections = record['request']['selected_sources']
        if selections:
            capability = self.capability(binding, selections)
            known = {(s['source_id'], s['version']) for s in capability['available_sources']}
            if not {(s['source_id'], s['version']) for s in selections} <= known:
                raise WorklistError('CONTEXT_STALE')

    def history(self, binding, conversation, cursor, limit):
        value = super().history(binding, conversation, cursor, limit)
        for record in value['turns']:
            self._source_authority(binding, record)
        return value

    def turn(self, binding, conversation, turn_id):
        value = super().turn(binding, conversation, turn_id)
        self._source_authority(binding, value['original_turn'])
        return value

    def _write(self, binding, path, body, kind, conversation, expected=None, *, authority):
        value = super()._write(binding, path, body, kind, conversation, expected, authority=authority)
        self.capability(binding, value['original_turn']['request']['selected_sources'])
        self._source_authority(binding, value['original_turn'])
        return value

    def catalog(self, binding, cursor=0, limit=4, snapshot=None):
        if type(cursor) is not int or not 0 <= cursor <= len(binding['conversation_ids']) or type(limit) is not int or not 1 <= limit <= 4:
            raise WorklistError('INVALID_REQUEST')
        query = {'cursor': cursor, 'limit': limit}
        if snapshot is not None:
            if not isinstance(snapshot, str) or re.fullmatch(r'sha256:[0-9a-f]{64}', snapshot) is None:
                raise WorklistError('INVALID_REQUEST')
            query['snapshot_revision'] = snapshot
        raw = self._read(binding, self.prefix+'/catalog?'+urlencode(query))
        value = wire.response(raw, 'catalog', binding, cursor=cursor, snapshot=snapshot)
        for item in value['items']:
            self.bound(binding, (binding['actor_id'], binding['workspace_project_id']), item['conversation_id'])
            source = self.turn(binding, item['conversation_id'], item['source_turn_id'])
            record = source['original_turn']
            if source['current_revision'] != item['conversation_revision']:
                raise WorklistError('CATALOG_SNAPSHOT_CHANGED')
            if record['status'] != 'COMPLETE' or record['request']['context_revision'] != item['context_revision'] or record['outcome']['output']['definition'] != item['definition']:
                raise WorklistError('INVALID_RESPONSE')
        return value

    def package(self, binding, conversation, revision=None):
        self.bound(binding,(binding['actor_id'],binding['workspace_project_id']),conversation)
        if revision is not None and (type(revision) is not int or not 1 <= revision <= 8):
            raise WorklistError('INVALID_REQUEST')
        query='' if revision is None else '?revision='+str(revision)
        value=wire.prepared(self._read(binding,self.prefix+'/'+conversation+'/package'+query),binding,conversation,revision=revision)
        if value['package'] is not None:
            frozen=value['package'];source=frozen['source']
            original=self.turn(binding,conversation,source['turn_id'])['original_turn']
            if (original['request_digest'] != source['request_digest'] or original['request']['context_revision'] != source['context_revision'] or
                original['session_id'] != source['session_id'] or original['invocation_id'] != source['invocation_id'] or
                original['outcome']['result_digest'] != source['result_digest'] or original['outcome']['output']['definition'] != frozen['definition']):
                raise WorklistError('INVALID_RESPONSE')
        return value

    def approve(self, binding, conversation, body, *, authority):
        self.bound(binding,(binding['actor_id'],binding['workspace_project_id']),conversation)
        wire.validate(body,'approve_request')
        package=self.package(binding,conversation,body['revision'])
        if package.get('package_digest') != body['package_digest']:
            raise WorklistError('CONCEPT_OR_CONTEXT_CHANGED')
        raw=control_request(binding,'POST',self.prefix+'/'+conversation+'/approve',body,gate=self._forward_gate(binding,authority),error_validator=wire.validate)
        self.capability(binding,[])
        return wire.compound(raw,binding,conversation,expected_digest=body['package_digest'],frozen=package['package'])

    def operation(self, binding, conversation, operation_id):
        from .review_peer import _id
        self.bound(binding,(binding['actor_id'],binding['workspace_project_id']),conversation)
        if not _id(operation_id):raise WorklistError('INVALID_REQUEST')
        raw=self._read(binding,self.prefix+'/'+conversation+'/operations/'+operation_id)
        return wire.compound(raw,binding,conversation,operation=operation_id)

    def resolve(self, binding, scope, body, *, authority):
        self.bound(binding,scope)
        try:wire.validate(body,'resolve_request')
        except WorklistError:raise WorklistError('INVALID_REQUEST') from None
        references=[body['workspace_conversation_id'],body['workspace_draft_id']]
        # Producer IDs are correlations only. Own current records authorize both references.
        def own_references():
            for reference in references:
                if re.fullmatch('[0-9a-f]{32}',reference) is None:
                    raise WorklistError('INVALID_REQUEST')
                try:self.conversations.get(scope,reference)
                except (FileNotFoundError,PermissionError):raise WorklistError('DENIED') from None
        own_references()
        from contextlib import contextmanager
        @contextmanager
        def current_authority():
            with authority:
                own_references()
                yield
        raw=control_request(binding,'POST',self.prefix+'/resolve',body,
            gate=self._forward_gate(binding,current_authority()),error_validator=wire.validate)
        wire.validate(raw,'resolve_result')
        resolved=raw['binding'];wire.scope(resolved['scope'],binding)
        expected=[binding['forge_instance_id']+':'+binding['actor_id'],resolved['scope'],*references]
        if (raw['operation_id']!=body['operation_id'] or
            resolved['principal_reference']!=expected[0] or
            resolved['workspace_conversation_id']!=references[0] or resolved['workspace_draft_id']!=references[1] or
            resolved['conversation_id'] not in binding['conversation_ids'] or resolved['binding_key']!=wire.digest(expected)):
            raise WorklistError('INVALID_RESPONSE')
        self.capability(binding,[]);own_references()
        return raw
