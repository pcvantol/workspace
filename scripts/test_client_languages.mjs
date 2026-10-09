import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {execFileSync} from 'node:child_process';
const serverOperations=JSON.parse(execFileSync('python3',['-c',"import json; from workspace_control.http import operation_inventory; print(json.dumps(operation_inventory('a'*32)))"],{encoding:'utf8'}));

function client({saved='system',system='en',storageFault=false}={}) {
  const elements=new Map();
  function element(id) {
    if (!elements.has(id)) elements.set(id,{value:'',textContent:'',children:[],listeners:{},dataset:{},
      addEventListener(type,handler){this.listeners[type]=handler;},
      replaceChildren(){this.children=[];},appendChild(row){this.children.push(row);}});
    return elements.get(id);
  }
  const translated=['languageLabel','systemLanguage','intro','tokenLabel','connect','forget','serverHeading','projectsHeading','capsHeading','note'].map(key=>{
    const e=element(key);e.dataset.i18n=key;return e;
  });
  const storage=new Map([['workspace.ui.language',saved]]);
  let requests=0;
  const document={documentElement:{},title:'',getElementById:element,querySelectorAll:()=>translated,createElement:()=>element(`row-${elements.size}`)};
  const context=vm.createContext({document,navigator:{language:system},localStorage:{
    getItem(key){if(storageFault)throw Error('denied');return storage.get(key)||null;},
    setItem(key,value){if(storageFault)throw Error('denied');storage.set(key,value);},
    removeItem(key){storage.delete(key);}},fetch:async path=>{
      requests++;
      const body=path==='/v1/identity'?{instance_id:'a'.repeat(32)}:
        path==='/v1/status'?{instance_id:'a'.repeat(32),version:serverOperations.product_version,state:'READY',project_source:'AVAILABLE'}:
        path==='/v1/capabilities'?serverOperations:
        path==='/v1/projects'?{state:'AVAILABLE',source:'DEMO',partial:false,stale:false,observed_at:'2026-10-08',projects:[{id:'source-id',name:'Original source text'}]}:null;
      return {ok:body!==null,status:body?200:503,json:async()=>body};
    }});
  vm.runInContext(fs.readFileSync('workspace_control/client.js','utf8'),context,{filename:fs.realpathSync('workspace_control/client.js')});
  return {element,storage,document,requests:()=>requests,change(language){element('language').value=language;element('language').listeners.change();},context};
}
const c=client();
c.element('token').value='unsent synthetic token';
await c.element('connect').listeners.click();
assert.equal(c.requests(),4);
assert.ok(c.element('capabilities').children.some(row=>row.textContent.startsWith('candidate.register')));
const labels={en:'Language',nl:'Taal',de:'Sprache',fr:'Langue',es:'Idioma'};
for(const [language,title] of Object.entries(labels)) {
  c.change(language);
  assert.equal(c.document.documentElement.lang,language);
  assert.equal(c.element('languageLabel').textContent,title);
  assert.equal(c.storage.get('workspace.ui.language'),language);
  assert.equal(c.element('token').value,'unsent synthetic token');
  assert.match(c.element('projects').children[0].textContent,/Original source text \(source-id\)/);
  assert.match(c.element('server').textContent,/a{32}/);
  assert.equal(c.requests(),4,'changing language must not call the server');
  assert.equal(client({saved:language}).document.documentElement.lang,language);
}
assert.equal(client({saved:'invalid',system:'nl-NL'}).document.documentElement.lang,'nl');
assert.equal(client({system:'ja-JP'}).document.documentElement.lang,'en');
const denied=client({storageFault:true,system:'fr-FR'});
denied.change('es');
assert.equal(denied.document.documentElement.lang,'es');
assert.equal(denied.requests(),0);
const pending=client();
const request=pending.element('connect').listeners.click();
pending.change('de');
await request;
assert.equal(pending.document.documentElement.lang,'de');
assert.equal(pending.element('state').textContent,'VERBUNDEN');
console.log('Five-language client selection, persistence, source preservation and zero-request switching passed.');
