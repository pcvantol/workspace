"""Map own saved briefing to the published R53 JOIN6161946949 input.

This pure mapping has no peer/provider call or source mutation. Producer ASCII
JSON digests differ intentionally from Workspace's existing UTF8 source digest.
Original own fields remain in the local snapshot; no truncation or inference.
"""
import hashlib
import json
import re
from .concept_briefing import VERSION, source, validate
from .concept_baseline_mapping import digest, text

CONTRACT = 'forge-preproject-concept-advisory/v1'
ROLES = {'BUSINESS': 'BUSINESS', 'ARCHITECT': 'ARCHITECTURE'}
LANGUAGES = {'en', 'nl', 'de', 'fr', 'es'}


class AdviceInputTooLong(ValueError):
    """Explicitly edit the source/message; never truncate it or invoke a model."""


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'),
                      ensure_ascii=True, allow_nan=False).encode('ascii')


def peer_digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def briefing(snapshot):
    if type(snapshot) is not dict or snapshot.get('briefing_version') != VERSION:
        raise ValueError('invalid saved briefing')
    own = source(snapshot['concept'], snapshot['fields'])
    if own['source_digest'] != snapshot['source_digest']:
        raise ValueError('saved source binding changed')
    fields = validate(own['fields'])
    # R53 publishes text|null, including the open_questions field. Preserve the
    # complete original own list separately, and send its explicit line text.
    fields['open_questions'] = '\n'.join(fields['open_questions'])
    for key, value in fields.items():
        if len(value) > 2000:
            raise AdviceInputTooLong('saved briefing field exceeds advice limit')
        fields[key] = value if value.strip() else None
    return {'concept_id': own['concept']['id'],
            'revision': own['concept']['revision'], 'fields': fields}


def prepare(snapshot, *, instance, dossier, conversation, operation, turn,
            expected_revision, role, language, message, transfer_digest):
    for identity in (instance, dossier, conversation, operation, turn):
        if not isinstance(identity, str) or re.fullmatch('[A-Za-z0-9][A-Za-z0-9._:-]{0,127}', identity) is None:
            raise ValueError('invalid configured advice identity')
    if type(expected_revision) is not int or not 0 <= expected_revision <= 1000000 or role not in ROLES or language not in LANGUAGES:
        raise ValueError('invalid advice context')
    if not isinstance(transfer_digest, str) or re.fullmatch('[0-9a-f]{64}', transfer_digest) is None:
        raise ValueError('explicit transfer policy required')
    if isinstance(message, str) and len(message) > 4000:
        raise AdviceInputTooLong('message exceeds advice limit')
    text(message, 4000)
    peer_briefing = briefing(snapshot)
    request = {'contract_version': CONTRACT, 'instance_id': instance,
               'dossier_id': dossier, 'conversation_id': conversation,
               'operation_id': operation, 'turn_id': turn,
               'expected_revision': expected_revision, 'briefing': peer_briefing,
               'briefing_digest': peer_digest(peer_briefing),
               'advisor_kind': ROLES[role], 'language': language,
               'message': message, 'transfer_policy_digest': transfer_digest}
    if len(canonical(request)) > 32768:
        raise AdviceInputTooLong('complete advice request exceeds byte limit')
    return {'own_source': json.loads(canonical(snapshot)), 'own_source_digest': snapshot['source_digest'],
            'request': request, 'request_digest': peer_digest(request),
            'peer_briefing_digest': request['briefing_digest'],
            'snapshot_digest': digest(snapshot)}
