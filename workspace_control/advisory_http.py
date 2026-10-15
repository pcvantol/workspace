"""Bounded advisory peer HTTP; forwarding fence is separate from long provider reads."""
from contextlib import nullcontext
import http.client
import json
import ssl
from .forge_peer import _endpoint
from .review_peer import _unique_pairs
from .worklist_peer import WorklistError
from .advisory_contract import validate

def request(binding, method, path, body=None, *, gate=None, error_validator=validate, maximum_bytes=65536, missing_as_state=None, proposal_audience=None, concept_audience=None, content_audience=None, send_guard=None, timeout=60):
    if sum(value is not None for value in (proposal_audience,concept_audience,content_audience))>1:
        raise WorklistError('INVALID_CONFIGURATION')
    audience=content_audience if content_audience is not None else concept_audience if concept_audience is not None else proposal_audience
    if audience is not None and (not isinstance(audience,str) or not 1<=len(audience)<=128 or any(ord(c)<32 or ord(c)>126 for c in audience)):
        raise WorklistError('INVALID_CONFIGURATION')
    scheme,host,port=_endpoint(binding['endpoint'])
    connection=(http.client.HTTPSConnection(host,port,timeout=timeout,context=ssl.create_default_context()) if scheme=='https' else http.client.HTTPConnection(host,port,timeout=timeout))
    try:
        payload=None if body is None else json.dumps(body,sort_keys=True,ensure_ascii=content_audience is None,separators=(',',':')).encode()
        if send_guard is not None:
            from .concept_baseline_dispatch import install_guarded_send
            connection.connect()  # DNS/TLS/connect wait holds no own authority lock.
            install_guarded_send(connection,send_guard,timeout)
        with gate or nullcontext():
            headers={'Authorization':'Bearer '+binding['forge_token'],'Content-Type':'application/json','Accept':'application/json'}
            if audience is not None:
                headers['X-Forge-Content-Audience' if content_audience is not None else 'X-Forge-Concept-Audience' if concept_audience is not None else 'X-Forge-Proposal-Audience']=audience
            connection.request(method,path,body=payload,headers=headers)
        response=connection.getresponse()
        if response.status in (401,403):raise WorklistError('DENIED')
        if response.status==404 and missing_as_state:raise WorklistError(missing_as_state)
        if response.getheader('Content-Type','').split(';',1)[0].lower()!='application/json':raise WorklistError('INVALID_RESPONSE')
        length=response.getheader('Content-Length')
        if length is not None and (not length.isdecimal() or int(length)>maximum_bytes):raise WorklistError('INVALID_RESPONSE')
        raw=response.read(maximum_bytes+1)
        if len(raw)>maximum_bytes:raise WorklistError('INVALID_RESPONSE')
        value=json.loads(raw,object_pairs_hook=_unique_pairs)
        if response.status!=200:
            error_validator(value,'error');raise WorklistError(value['error']['code'],http_status=response.status)
        return value
    except WorklistError:raise
    except (ssl.SSLCertVerificationError,ssl.CertificateError):raise WorklistError('TLS_UNTRUSTED') from None
    except (OSError,TimeoutError,http.client.HTTPException):raise WorklistError('UNAVAILABLE') from None
    except (ValueError,UnicodeError,RecursionError):raise WorklistError('INVALID_RESPONSE') from None
    finally:connection.close()
