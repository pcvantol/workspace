"""Only saved human context and explicitly owner-bound references; no inferred inventory."""
from .concept_baseline_mapping import map_concept,digest,DescriptionRequired,UNKNOWN
from .concept_adoption_wire import CONTRACT,check
CATALOG=('docs/product/VISION.md','docs/architecture/ARCHITECTURE.md','docs/roadmap/ROADMAP.md')

def mapping(source,scope,binding,command):
    selected=command['requested_artifacts'];choices=command['mappings']
    if type(selected) is not list or not 1<=len(selected)<=3 or len(set(selected))!=len(selected) or not set(selected)<=set(CATALOG):raise ValueError('catalogue selection required')
    if type(choices) is not list or len(choices)>len(selected):raise ValueError('invalid document mappings')
    seen=set()
    for choice in choices:
        if type(choice) is not dict or set(choice)!={'artifact_path','source_path','choice'} or choice['artifact_path'] not in selected or choice['artifact_path'] in seen or choice['source_path'] not in binding['source_options'] or choice['choice']!='LINK_EXISTING':raise ValueError('owner-allowed existing document reference required')
        seen.add(choice['artifact_path'])
    identity=binding['identity'];references={k:identity[k] for k in ('project_id','repository_id','owner_reference')}
    try:base=map_concept(source,scope,references)
    except DescriptionRequired:base=map_concept(source,scope,references,description=UNKNOWN)
    base['input']['identity']=dict(identity);base['input']['authority_contract_reference']=identity['authority_repository_id']+':engineering/project-contract.json'
    value={'bootstrap_input':base['input'],'requested_artifacts':selected,'mappings':choices}
    check(value,'Input');return {'source':base['source'],'source_digest':base['source_digest'],'input':value,'input_digest':digest(value),'unknown_fields':base['unknown_fields']}

def request_for(mapped,binding,operation):
    value={'contract_version':CONTRACT,'instance_id':binding['instance_id'],'dossier_id':binding['dossier_id'],'operation_id':operation,'pairing_id':binding['pairing_id'],'input':mapped['input']}
    check(value,'Request');return value
