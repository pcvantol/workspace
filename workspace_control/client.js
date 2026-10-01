const state = document.getElementById('state');
const server = document.getElementById('server');
const projectState = document.getElementById('project-state');
const projects = document.getElementById('projects');
const capabilityState = document.getElementById('capability-state');
const peerState = document.getElementById('peer-state');
const capabilities = document.getElementById('capabilities');
let connectionAttempt = 0;
function clearCapabilities() {
  capabilityState.textContent = 'UNAVAILABLE';
  peerState.textContent = 'Peer operations: UNQUALIFIED';
  capabilities.replaceChildren();
}
document.getElementById('forget').addEventListener('click', () => {
  connectionAttempt += 1;
  localStorage.removeItem('workspace.instanceId');
  document.getElementById('token').value = '';
  state.textContent = 'UNCONFIGURED';
  server.textContent = 'No server binding';
  projectState.textContent = 'UNCONFIGURED';
  projects.replaceChildren();
  clearCapabilities();
});
document.getElementById('connect').addEventListener('click', async () => {
  const attempt = ++connectionAttempt;
  state.textContent = 'CONNECTING';
  projects.replaceChildren();
  clearCapabilities();
  try {
    const identityResponse = await fetch('/v1/identity', {cache: 'no-store'});
    if (attempt !== connectionAttempt) return;
    if (!identityResponse.ok) throw new Error('UNAVAILABLE');
    const identity = await identityResponse.json();
    if (attempt !== connectionAttempt) return;
    const pinned = localStorage.getItem('workspace.instanceId');
    if (pinned && pinned !== identity.instance_id) throw new Error('WRONG_INSTANCE');
    const token = document.getElementById('token').value;
    const headers = {'Authorization': `Bearer ${token}`, 'X-Workspace-Instance': identity.instance_id};
    const statusResponse = await fetch('/v1/status', {headers, cache: 'no-store'});
    if (attempt !== connectionAttempt) return;
    if (statusResponse.status === 401) throw new Error('UNAUTHORIZED');
    if (statusResponse.status === 409) throw new Error('WRONG_INSTANCE');
    if (!statusResponse.ok) throw new Error('UNAVAILABLE');
    const status = await statusResponse.json();
    if (attempt !== connectionAttempt) return;
    if (!pinned) localStorage.setItem('workspace.instanceId', identity.instance_id);
    state.textContent = 'CONNECTED';
    server.textContent = `${status.instance_id} · version ${status.version} · ${status.state}`;
    const capabilityResponse = await fetch('/v1/capabilities', {headers, cache: 'no-store'});
    if (attempt !== connectionAttempt) return;
    if (capabilityResponse.status === 401) throw new Error('UNAUTHORIZED');
    if (capabilityResponse.status === 409) throw new Error('WRONG_INSTANCE');
    if (capabilityResponse.ok) {
      const inventory = await capabilityResponse.json();
      if (attempt !== connectionAttempt) return;
      if (inventory.schema_version === 1 && inventory.instance_id === identity.instance_id &&
          inventory.peer_operations_qualified === false && Array.isArray(inventory.operations) &&
          inventory.operations.every(operation => typeof operation.id === 'string' &&
            ['HTTP_EXPOSED', 'LOCAL_ONLY_ADMIN'].includes(operation.exposure))) {
        capabilityState.textContent = 'AVAILABLE';
        for (const operation of inventory.operations) {
          const row = document.createElement('li');
          row.textContent = `${operation.id} · ${operation.exposure}`;
          capabilities.appendChild(row);
        }
      }
    }
    const projectResponse = await fetch('/v1/projects', {headers, cache: 'no-store'});
    if (attempt !== connectionAttempt) return;
    if (projectResponse.status === 503) {
      projectState.textContent = 'UNAVAILABLE';
      return;
    }
    if (!projectResponse.ok) throw new Error('UNAUTHORIZED');
    const catalogue = await projectResponse.json();
    if (attempt !== connectionAttempt) return;
    const labels = [catalogue.state];
    if (catalogue.stale && catalogue.partial) labels.push('PARTIAL');
    if (catalogue.projects.length === 0 && !['EMPTY', 'UNCONFIGURED'].includes(catalogue.state)) labels.push('EMPTY');
    if (catalogue.source) labels.push(catalogue.source);
    projectState.textContent = labels.join(' · ');
    for (const item of catalogue.projects) {
      const row = document.createElement('li');
      row.textContent = `${item.name} (${item.id})${catalogue.source === 'DEMO' ? ' · DEMO' : ''}`;
      projects.appendChild(row);
    }
  } catch (error) {
    if (attempt !== connectionAttempt) return;
    state.textContent = error.message === 'UNAUTHORIZED' ? 'UNAUTHORIZED' :
      error.message === 'WRONG_INSTANCE' ? 'WRONG INSTANCE' : 'UNAVAILABLE';
    server.textContent = 'No connection';
    projectState.textContent = 'UNAVAILABLE';
    projects.replaceChildren();
    clearCapabilities();
  }
});
