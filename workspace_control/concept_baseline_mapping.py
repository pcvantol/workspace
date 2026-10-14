"""Map an authorized saved concept to the sole published R50 document profile.

No renderer, extraction/model, identity registration or peer operation occurs here.
Unknown required fields remain explicitly unknown; source text is never truncated.
"""
import hashlib
import json
import re
import secrets
from importlib.resources import files
from .advisory_contract import _check

CONTRACT = 'workspace-concept-baseline/1'
PROFILE = {'contract_version':'pb-render/1.0','baseline':'portable-docs/1.0.0',
           'mode':'GENESIS','role':'authority','document_language':'en',
           'host_profile':'LOCAL_POSIX','stack_profile':'NO_PRODUCT_CODE',
           'security_profile':'DOCUMENT_ONLY','license_profile':'UNDECIDED'}
UNKNOWN = 'Not supplied in this project concept.'
QUESTIONS = {'purpose':'What purpose should this idea serve?',
             'users':'Who should this idea serve?',
             'non_goals':'What should remain outside the project?',
             'constraints':'Which constraints need to be considered?'}
_SCHEMA = json.loads(files('workspace_control').joinpath('project-concept-baseline-input-v1.json').read_text())

class DescriptionRequired(ValueError):
    """Explicit shorter purpose required; original notes remain unchanged."""


def canonical(value):
    return json.dumps(value,sort_keys=True,separators=(',', ':'),ensure_ascii=False,allow_nan=False).encode('utf-8')


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def text(value, maximum, *, blank=False):
    if not isinstance(value,str) or len(value)>maximum or (not blank and not value.strip()) or any(ord(c)<32 and c not in '\t\n' for c in value):
        raise ValueError('invalid concept text')
    return value


def provisional_references():
    # Cryptographically random, not derived from title/path/endpoint/context.
    return {'project_id':'proposal-project-'+secrets.token_hex(16),
            'repository_id':'proposal-authority-'+secrets.token_hex(16),
            'owner_reference':'proposal-owner-'+secrets.token_hex(16)}


def map_concept(concept, scope, references, description=None):
    if type(concept) is not dict or len(scope)!=2 or concept.get('actor_id')!=scope[0] or concept.get('context_id')!=scope[1]:
        raise PermissionError('concept scope denied')
    identity=concept.get('id');revision=concept.get('revision')
    if not isinstance(identity,str) or re.fullmatch('[0-9a-f]{32}',identity) is None or type(revision) is not int or not 1<=revision<=1000001 or concept.get('state')!='CONCEPT_NOT_CONFIGURED':
        raise ValueError('invalid saved concept')
    title=text(concept.get('title'),120);notes=text(concept.get('notes'),10000,blank=True)
    if type(references) is not dict or set(references)!={'project_id','repository_id','owner_reference'}:
        raise ValueError('invalid provisional references')
    for key,value in references.items():
        text(value,256 if key=='owner_reference' else 128)
        if key!='owner_reference' and re.fullmatch('[a-z0-9][a-z0-9._-]{2,127}',value) is None:
            raise ValueError('invalid provisional reference')
    if description is None:
        purpose=notes if notes.strip() and len(notes)<=4096 else UNKNOWN
    else:
        purpose=text(description,4096)
    product_fields={key:UNKNOWN for key in ('users','non_goals','constraints')}
    briefing=concept.get('briefing')
    questions=[]
    if briefing is not None:
        from .concept_briefing import validate
        if type(briefing) is not dict or set(briefing)!={'fields','accepted_from'} or type(briefing['accepted_from']) is not dict or not briefing['accepted_from'] or len(canonical(briefing))>64000:
            raise ValueError('invalid accepted briefing')
        values=validate(briefing['fields'])
        if values['name']!=title:raise ValueError('briefing title changed')
        if description is None and values['purpose'].strip():purpose=values['purpose']
        product_fields={key:values[key] if values[key].strip() else UNKNOWN for key in product_fields}
        questions=list(values['open_questions'])
    if description is None and len(notes)>4096 and purpose==UNKNOWN:
        raise DescriptionRequired('choose a purpose of at most4096characters')
    unknown=[key for key,value in product_fields.items() if value==UNKNOWN]
    if purpose==UNKNOWN:unknown.insert(0,'purpose')
    snapshot={key:concept[key] for key in ('id','actor_id','context_id','revision','title','notes','state')}
    if briefing is not None:snapshot['briefing']=briefing
    source_digest=digest(snapshot)
    choice={'source_digest':source_digest,'purpose':purpose,'unknown_fields':unknown}
    result={**PROFILE,'identity':{'status':'PROVISIONAL_REFERENCE',**references,'authority_repository_id':references['repository_id']},
            'product':{'name':title,'purpose':purpose,**product_fields,'open_questions':list(dict.fromkeys(questions+[QUESTIONS[key] for key in unknown]))},
            'authority_contract_reference':references['repository_id']+':engineering/project-contract.json',
            'source_references':[{'owner':'USER_DECLARED','reference':f'workspace-concept:{identity}:revision:{revision}','digest':source_digest},
                                 {'owner':'USER_DECLARED','reference':f'workspace-concept-purpose-choice:{identity}:revision:{revision}','digest':digest(choice)}]}
    if briefing is not None:
        result['source_references'].append({'owner':'USER_DECLARED','reference':f'workspace-concept-accepted-briefing:{identity}:revision:{revision}','digest':digest(briefing)})
    _check(result,_SCHEMA,{})
    if len(canonical(result))>64000:raise ValueError('mapping byte limit')
    return {'contract_version':CONTRACT,'source':snapshot,'source_digest':source_digest,'choice':choice,
            'input':result,'input_digest':digest(result),'status':'PROPOSAL_PROJECT_NOT_CONFIGURED',
            'unknown_fields':unknown,'document_language':'en'}
