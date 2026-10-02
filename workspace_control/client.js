const translations = {
  en: {
    title: 'Workspace Client',
    intro: 'Read-only Server status and project information', tokenLabel: 'Instance token',
    tokenPlaceholder: 'Paste the token from your private data root', connect: 'Connect',
    forget: 'Forget server binding', serverHeading: 'Server', projectsHeading: 'Projects',
    capsHeading: 'Server capabilities', noConnection: 'No connection',
    noBinding: 'No server binding', noObservation: 'No observation', observed: 'Observed',
    version: 'version', peerOperations: 'Peer operations',
    note: 'Project information is Workspace-owned local data. Demo entries are labelled DEMO. Forge and Engineering Platform sources are unconfigured.',
    labels: {UNAVAILABLE: 'UNAVAILABLE', UNCONFIGURED: 'UNCONFIGURED', CONNECTING: 'CONNECTING',
      CONNECTED: 'CONNECTED', UNAUTHORIZED: 'UNAUTHORIZED', WRONG_INSTANCE: 'WRONG INSTANCE',
      AVAILABLE: 'AVAILABLE', STALE: 'STALE', PARTIAL: 'PARTIAL', EMPTY: 'EMPTY',
      LOCAL: 'LOCAL', DEMO: 'DEMO', READY: 'READY', UNQUALIFIED: 'UNQUALIFIED',
      HTTP_EXPOSED: 'HTTP_EXPOSED', LOCAL_ONLY_ADMIN: 'LOCAL_ONLY_ADMIN'}
  },
  nl: {
    title: 'Workspace-client',
    intro: 'Alleen-lezen serverstatus en projectinformatie', tokenLabel: 'Instantietoken',
    tokenPlaceholder: 'Plak het token uit uw privégegevensmap', connect: 'Verbinden',
    forget: 'Serverbinding vergeten', serverHeading: 'Server', projectsHeading: 'Projecten',
    capsHeading: 'Servermogelijkheden', noConnection: 'Geen verbinding',
    noBinding: 'Geen serverbinding', noObservation: 'Geen waarneming', observed: 'Waargenomen',
    version: 'versie', peerOperations: 'Peeroperaties',
    note: 'Projectinformatie is lokale data van Workspace. Demo-items zijn gemarkeerd als DEMO. Forge- en Engineering Platform-bronnen zijn niet geconfigureerd.',
    labels: {UNAVAILABLE: 'NIET BESCHIKBAAR', UNCONFIGURED: 'NIET GECONFIGUREERD', CONNECTING: 'VERBINDING MAKEN',
      CONNECTED: 'VERBONDEN', UNAUTHORIZED: 'GEEN TOEGANG', WRONG_INSTANCE: 'VERKEERDE INSTANTIE',
      AVAILABLE: 'BESCHIKBAAR', STALE: 'VEROUDERD', PARTIAL: 'GEDEELTELIJK', EMPTY: 'LEEG',
      LOCAL: 'LOKAAL', DEMO: 'DEMO', READY: 'GEREED', UNQUALIFIED: 'NIET GEKWALIFICEERD',
      HTTP_EXPOSED: 'VIA HTTP', LOCAL_ONLY_ADMIN: 'ALLEEN LOKAAL BEHEER'}
  },
  de: {
    title: 'Workspace-Oberfläche',
    intro: 'Schreibgeschützter Serverstatus und Projektinformationen', tokenLabel: 'Instanztoken',
    tokenPlaceholder: 'Token aus dem privaten Datenverzeichnis einfügen', connect: 'Verbinden',
    forget: 'Serverbindung vergessen', serverHeading: 'Server', projectsHeading: 'Projekte',
    capsHeading: 'Serverfunktionen', noConnection: 'Keine Verbindung',
    noBinding: 'Keine Serverbindung', noObservation: 'Keine Beobachtung', observed: 'Beobachtet',
    version: 'Version', peerOperations: 'Peer-Operationen',
    note: 'Projektinformationen sind lokale Workspace-Daten. Demo-Einträge sind als DEMO gekennzeichnet. Forge- und Engineering-Platform-Quellen sind nicht konfiguriert.',
    labels: {UNAVAILABLE: 'NICHT VERFÜGBAR', UNCONFIGURED: 'NICHT KONFIGURIERT', CONNECTING: 'VERBINDUNG WIRD HERGESTELLT',
      CONNECTED: 'VERBUNDEN', UNAUTHORIZED: 'NICHT AUTORISIERT', WRONG_INSTANCE: 'FALSCHE INSTANZ',
      AVAILABLE: 'VERFÜGBAR', STALE: 'VERALTET', PARTIAL: 'TEILWEISE', EMPTY: 'LEER',
      LOCAL: 'LOKAL', DEMO: 'DEMO', READY: 'BEREIT', UNQUALIFIED: 'NICHT QUALIFIZIERT',
      HTTP_EXPOSED: 'ÜBER HTTP', LOCAL_ONLY_ADMIN: 'NUR LOKALE VERWALTUNG'}
  },
  fr: {
    title: 'Interface Workspace',
    intro: 'État du serveur et informations sur les projets en lecture seule', tokenLabel: 'Jeton d’instance',
    tokenPlaceholder: 'Collez le jeton de votre répertoire de données privé', connect: 'Se connecter',
    forget: 'Oublier la liaison au serveur', serverHeading: 'Serveur', projectsHeading: 'Projets',
    capsHeading: 'Fonctions du serveur', noConnection: 'Aucune connexion',
    noBinding: 'Aucune liaison au serveur', noObservation: 'Aucune observation', observed: 'Observé',
    version: 'version', peerOperations: 'Opérations des pairs',
    note: 'Les informations sur les projets sont des données locales de Workspace. Les entrées de démonstration portent la mention DÉMO. Les sources Forge et Engineering Platform ne sont pas configurées.',
    labels: {UNAVAILABLE: 'INDISPONIBLE', UNCONFIGURED: 'NON CONFIGURÉ', CONNECTING: 'CONNEXION EN COURS',
      CONNECTED: 'CONNECTÉ', UNAUTHORIZED: 'NON AUTORISÉ', WRONG_INSTANCE: 'MAUVAISE INSTANCE',
      AVAILABLE: 'DISPONIBLE', STALE: 'PÉRIMÉ', PARTIAL: 'PARTIEL', EMPTY: 'VIDE',
      LOCAL: 'LOCAL', DEMO: 'DÉMO', READY: 'PRÊT', UNQUALIFIED: 'NON QUALIFIÉ',
      HTTP_EXPOSED: 'PAR HTTP', LOCAL_ONLY_ADMIN: 'ADMINISTRATION LOCALE UNIQUEMENT'}
  },
  es: {
    title: 'Cliente de Workspace',
    intro: 'Estado del servidor e información de proyectos de solo lectura', tokenLabel: 'Token de instancia',
    tokenPlaceholder: 'Pegue el token de su directorio privado de datos', connect: 'Conectar',
    forget: 'Olvidar vínculo del servidor', serverHeading: 'Servidor', projectsHeading: 'Proyectos',
    capsHeading: 'Funciones del servidor', noConnection: 'Sin conexión',
    noBinding: 'Sin vínculo del servidor', noObservation: 'Sin observación', observed: 'Observado',
    version: 'versión', peerOperations: 'Operaciones de pares',
    note: 'La información de proyectos son datos locales de Workspace. Las entradas de demostración llevan la etiqueta DEMO. Las fuentes de Forge y Engineering Platform no están configuradas.',
    labels: {UNAVAILABLE: 'NO DISPONIBLE', UNCONFIGURED: 'SIN CONFIGURAR', CONNECTING: 'CONECTANDO',
      CONNECTED: 'CONECTADO', UNAUTHORIZED: 'NO AUTORIZADO', WRONG_INSTANCE: 'INSTANCIA INCORRECTA',
      AVAILABLE: 'DISPONIBLE', STALE: 'DESACTUALIZADO', PARTIAL: 'PARCIAL', EMPTY: 'VACÍO',
      LOCAL: 'LOCAL', DEMO: 'DEMO', READY: 'LISTO', UNQUALIFIED: 'NO CALIFICADO',
      HTTP_EXPOSED: 'POR HTTP', LOCAL_ONLY_ADMIN: 'SOLO ADMINISTRACIÓN LOCAL'}
  }
};
const locale = (navigator.language || 'en').toLowerCase().split('-')[0];
const language = Object.hasOwn(translations, locale) ? locale : 'en';
const copy = translations[language];
const label = value => copy.labels[value] || value;
document.documentElement.lang = language;
document.title = copy.title;
for (const element of document.querySelectorAll('[data-i18n]')) {
  element.textContent = copy[element.dataset.i18n];
}
document.getElementById('token').placeholder = copy.tokenPlaceholder;
const state = document.getElementById('state');
const server = document.getElementById('server');
const projectState = document.getElementById('project-state');
const projectObserved = document.getElementById('project-observed');
const projects = document.getElementById('projects');
const capabilityState = document.getElementById('capability-state');
const peerState = document.getElementById('peer-state');
const capabilities = document.getElementById('capabilities');
state.textContent = label('UNAVAILABLE');
server.textContent = copy.noConnection;
projectState.textContent = label('UNAVAILABLE');
projectObserved.textContent = copy.noObservation;
capabilityState.textContent = label('UNAVAILABLE');
peerState.textContent = `${copy.peerOperations}: ${label('UNQUALIFIED')}`;
let connectionAttempt = 0;
function clearCapabilities() {
  capabilityState.textContent = label('UNAVAILABLE');
  peerState.textContent = `${copy.peerOperations}: ${label('UNQUALIFIED')}`;
  capabilities.replaceChildren();
}
document.getElementById('forget').addEventListener('click', () => {
  connectionAttempt += 1;
  localStorage.removeItem('workspace.instanceId');
  document.getElementById('token').value = '';
  state.textContent = label('UNCONFIGURED');
  server.textContent = copy.noBinding;
  projectState.textContent = label('UNCONFIGURED');
  projectObserved.textContent = copy.noObservation;
  projects.replaceChildren();
  clearCapabilities();
});
document.getElementById('connect').addEventListener('click', async () => {
  const attempt = ++connectionAttempt;
  state.textContent = label('CONNECTING');
  server.textContent = copy.noConnection;
  projectState.textContent = label('UNAVAILABLE');
  projects.replaceChildren();
  projectObserved.textContent = copy.noObservation;
  clearCapabilities();
  try {
    const identityResponse = await fetch('/v1/identity', {cache: 'no-store'});
    if (attempt !== connectionAttempt) return;
    if (!identityResponse.ok) throw new Error('UNAVAILABLE');
    const identity = await identityResponse.json();
    if (attempt !== connectionAttempt) return;
    if (typeof identity.instance_id !== 'string' || !/^[0-9a-f]{32}$/.test(identity.instance_id)) {
      throw new Error('UNAVAILABLE');
    }
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
    if (status.instance_id !== identity.instance_id) throw new Error('WRONG_INSTANCE');
    if (!pinned) localStorage.setItem('workspace.instanceId', identity.instance_id);
    state.textContent = label('CONNECTED');
    server.textContent = `${status.instance_id} · ${copy.version} ${status.version} · ${label(status.state)}`;
    const capabilityResponse = await fetch('/v1/capabilities', {headers, cache: 'no-store'});
    if (attempt !== connectionAttempt) return;
    if (capabilityResponse.status === 401) throw new Error('UNAUTHORIZED');
    if (capabilityResponse.status === 409) throw new Error('WRONG_INSTANCE');
    if (capabilityResponse.ok) {
      const inventory = await capabilityResponse.json();
      if (attempt !== connectionAttempt) return;
      if (typeof inventory.instance_id === 'string' && inventory.instance_id !== identity.instance_id) {
        throw new Error('WRONG_INSTANCE');
      }
      if (inventory.schema_version === 1 && inventory.instance_id === identity.instance_id &&
          inventory.product_version === status.version &&
          inventory.peer_operations_qualified === false && Array.isArray(inventory.operations) &&
          inventory.operations.every(operation => operation && typeof operation.id === 'string' &&
            operation.id.trim().length > 0 &&
            ['HTTP_EXPOSED', 'LOCAL_ONLY_ADMIN'].includes(operation.exposure)) &&
          new Set(inventory.operations.map(operation => operation.id)).size === inventory.operations.length) {
        capabilityState.textContent = label('AVAILABLE');
        for (const operation of inventory.operations) {
          const row = document.createElement('li');
          row.textContent = `${operation.id} · ${label(operation.exposure)}`;
          capabilities.appendChild(row);
        }
      }
    }
    const projectResponse = await fetch('/v1/projects', {headers, cache: 'no-store'});
    if (attempt !== connectionAttempt) return;
    if (projectResponse.status === 503) {
      projectState.textContent = label('UNAVAILABLE');
      return;
    }
    if (projectResponse.status === 401) throw new Error('UNAUTHORIZED');
    if (projectResponse.status === 409) throw new Error('WRONG_INSTANCE');
    if (!projectResponse.ok) throw new Error('UNAVAILABLE');
    const catalogue = await projectResponse.json();
    if (attempt !== connectionAttempt) return;
    if (catalogue.state !== 'UNCONFIGURED' &&
        (typeof catalogue.observed_at !== 'string' || catalogue.observed_at.length === 0)) {
      throw new Error('UNAVAILABLE');
    }
    const labels = [catalogue.state];
    if (catalogue.stale && catalogue.partial) labels.push('PARTIAL');
    if (catalogue.projects.length === 0 && !['EMPTY', 'UNCONFIGURED'].includes(catalogue.state)) labels.push('EMPTY');
    if (catalogue.source) labels.push(catalogue.source);
    projectState.textContent = labels.map(label).join(' · ');
    projectObserved.textContent = catalogue.state === 'UNCONFIGURED' ?
      copy.noObservation : `${copy.observed}: ${catalogue.observed_at}`;
    for (const item of catalogue.projects) {
      const row = document.createElement('li');
      row.textContent = `${item.name} (${item.id})${catalogue.source === 'DEMO' ? ` · ${label('DEMO')}` : ''}`;
      projects.appendChild(row);
    }
  } catch (error) {
    if (attempt !== connectionAttempt) return;
    state.textContent = label(error.message === 'UNAUTHORIZED' ? 'UNAUTHORIZED' :
      error.message === 'WRONG_INSTANCE' ? 'WRONG_INSTANCE' : 'UNAVAILABLE');
    server.textContent = copy.noConnection;
    projectState.textContent = label('UNAVAILABLE');
    projectObserved.textContent = copy.noObservation;
    projects.replaceChildren();
    clearCapabilities();
  }
});
