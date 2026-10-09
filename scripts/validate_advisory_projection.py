"""Pinned external wire schema projection drift; no producer implementation imported."""
from hashlib import sha256
import json
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
raw=(root/'workspace_control/advisory-conversation-v1.json').read_bytes()
if sha256(raw).hexdigest()!='fc4750604a4f063d11a1680d9d5ca77ade4784cff53692b40692e86d6c26e7ef':raise ValueError('advisory producer schema pin drift')
swift=(root/'macos/WorkspaceClient/Sources/WorkspaceClient/AdvisoryWire.swift').read_text()
match=re.search(r'Data\(###"(.+?)"###\.utf8\)',swift)
if match is None or json.loads(match[1])!=json.loads(raw):raise ValueError('native advisory schema projection drift')
print('Pinned Forge2.8.0 advisory wire projections match.')

candidate=(root/'workspace_control/advisory-candidate-v1.json').read_bytes()
if sha256(candidate).hexdigest()!='d5f33e93f9e00922c39b5b7b0bc93c1ab6413cdc2cffac0575965416342b0261':raise ValueError('Candidate producer schema pin drift')
swift=(root/'macos/WorkspaceClient/Sources/WorkspaceClient/CandidateWire.swift').read_text()
match=re.search(r'Data\(###"(.+?)"###\.utf8\)',swift)
if match is None or json.loads(match[1])!=json.loads(candidate):raise ValueError('native Candidate schema projection drift')
print('Pinned Forge2.9.0 Candidate wire projections match.')

# Actual L3 schema preview, not a qualified final producer pin.
import base64
mission=(root/'workspace_control/mission-concepts-v1.json').read_bytes()
if sha256(mission).hexdigest()!='0311529ca95451a99f4fd8a35127707310252c96324b42f3230e8c79fcfa6124':raise ValueError('mission concept schema preview drift')
swift=(root/'macos/WorkspaceClient/Sources/WorkspaceClient/MissionConceptWire.swift').read_text()
match=re.search(r'Data\(base64Encoded: "([A-Za-z0-9+/=]+)"\)',swift)
if match is None or base64.b64decode(match[1])!=mission:raise ValueError('native mission concept schema preview drift')
print('Actual producer mission concept preview matches; final qualification pending.')
