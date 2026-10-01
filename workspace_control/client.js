const state = document.getElementById('state');
const server = document.getElementById('server');
const projectState = document.getElementById('project-state');
const projects = document.getElementById('projects');
document.getElementById('forget').addEventListener('click', () => {
  localStorage.removeItem('workspace.instanceId');
  state.textContent = 'UNCONFIGURED';
  server.textContent = 'No server binding';
  projectState.textContent = 'UNCONFIGURED';
  projects.replaceChildren();
});
document.getElementById('connect').addEventListener('click', async () => {
  state.textContent = 'CONNECTING';
  projects.replaceChildren();
  try {
    const identityResponse = await fetch('/v1/identity', {cache: 'no-store'});
    if (!identityResponse.ok) throw new Error('UNAVAILABLE');
    const identity = await identityResponse.json();
    const pinned = localStorage.getItem('workspace.instanceId');
    if (pinned && pinned !== identity.instance_id) throw new Error('WRONG_INSTANCE');
    const token = document.getElementById('token').value;
    const headers = {'Authorization': `Bearer ${token}`, 'X-Workspace-Instance': identity.instance_id};
    const statusResponse = await fetch('/v1/status', {headers, cache: 'no-store'});
    if (statusResponse.status === 401) throw new Error('UNAUTHORIZED');
    if (statusResponse.status === 409) throw new Error('WRONG_INSTANCE');
    if (!statusResponse.ok) throw new Error('UNAVAILABLE');
    const status = await statusResponse.json();
    const projectResponse = await fetch('/v1/projects', {headers, cache: 'no-store'});
    if (!projectResponse.ok) throw new Error(projectResponse.status === 503 ? 'UNAVAILABLE' : 'UNAUTHORIZED');
    const catalogue = await projectResponse.json();
    if (!pinned) localStorage.setItem('workspace.instanceId', identity.instance_id);
    state.textContent = 'CONNECTED';
    server.textContent = `${status.instance_id} · version ${status.version} · ${status.state}`;
    projectState.textContent = `${catalogue.state}${catalogue.source ? ` · ${catalogue.source}` : ''}`;
    for (const item of catalogue.projects) {
      const row = document.createElement('li');
      row.textContent = `${item.name} (${item.id})${catalogue.source === 'DEMO' ? ' · DEMO' : ''}`;
      projects.appendChild(row);
    }
  } catch (error) {
    state.textContent = error.message === 'UNAUTHORIZED' ? 'UNAUTHORIZED' :
      error.message === 'WRONG_INSTANCE' ? 'WRONG INSTANCE' : 'UNAVAILABLE';
    server.textContent = 'No connection';
    projectState.textContent = 'UNAVAILABLE';
  }
});
