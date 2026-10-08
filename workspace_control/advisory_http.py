"""Bounded advisory peer HTTP; forwarding fence is separate from long provider reads."""
from contextlib import nullcontext
import http.client
import json
import ssl
from .forge_peer import _endpoint
from .review_peer import _unique_pairs
from .worklist_peer import WorklistError
from .advisory_contract import validate

def request(binding, method, path, body=None, *, gate=None, error_validator=validate):
    scheme,host,port=_endpoint(binding['endpoint'])
    connection=(http.client.HTTPSConnection(host,port,timeout=60,context=ssl.create_default_context()) if scheme=='https' else http.client.HTTPConnection(host,port,timeout=60))
    try:
        payload=None if body is None else json.dumps(body,sort_keys=True,ensure_ascii=True,separators=(',',':')).encode()
        with gate or nullcontext():
            connection.request(method,path,body=payload,headers={'Authorization':'Bearer '+binding['forge_token'],'Content-Type':'application/json','Accept':'application/json'})
        response=connection.getresponse()
        if response.status in (401,403):raise WorklistError('DENIED')
        if response.getheader('Content-Type','').split(';',1)[0].lower()!='application/json':raise WorklistError('INVALID_RESPONSE')
        length=response.getheader('Content-Length')
        if length is not None and (not length.isdecimal() or int(length)>65536):raise WorklistError('INVALID_RESPONSE')
        raw=response.read(65537)
        if len(raw)>65536:raise WorklistError('INVALID_RESPONSE')
        value=json.loads(raw,object_pairs_hook=_unique_pairs)
        if response.status!=200:
            error_validator(value,'error');raise WorklistError(value['error']['code'])
        return value
    except WorklistError:raise
    except (ssl.SSLCertVerificationError,ssl.CertificateError):raise WorklistError('TLS_UNTRUSTED') from None
    except (OSError,TimeoutError,http.client.HTTPException):raise WorklistError('UNAVAILABLE') from None
    except (ValueError,UnicodeError,RecursionError):raise WorklistError('INVALID_RESPONSE') from None
    finally:connection.close()
