import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import { insertEditorAction } from '../../entry/src/main/ets/document/EditorActions.ts';
import { imageLabel, usePreviewText } from '../src/preview-text.ts';

// Run the actual checked-out source; replace only platform-dependent imports.
function load(relative, exported, context = {}) {
  const path = new URL('../../entry/src/main/ets/' + relative, import.meta.url);
  const source = readFileSync(path, 'utf8').replace(/^import .*;\s*$/gm, '').replace(/^export /gm, '');
  return vm.runInNewContext(`${stripTypeScriptTypes(source)}\n${exported}`, context);
}
const wantConstant = { Params: { PARAMS_STREAM: 'stream' },
  Flags: { FLAG_AUTH_READ_URI_PERMISSION: 1, FLAG_AUTH_WRITE_URI_PERMISSION: 2 } };
test('all startup file requests survive until the page binds', () => {
  const queue=load('document/LaunchRequests.ets','LaunchRequests',{wantConstant}), received=[];
  queue.deliver({uri:'A.md'});queue.deliver({uri:'B.md'});queue.bind(r=>received.push(r.uri));
  assert.deepEqual(received,['A.md','B.md']);
});
test('reentrant startup requests do not overtake pending files', () => {
  const queue=load('document/LaunchRequests.ets','LaunchRequests',{wantConstant}), received=[];
  queue.deliver({uri:'A.md'});queue.deliver({uri:'B.md'});
  queue.bind(r=>{received.push(r.uri);if(r.uri==='A.md')queue.deliver({uri:'C.md'});});
  assert.deepEqual(received,['A.md','B.md','C.md']);
});
test('toolbar commands have an independent undo boundary', () => {
  const History=load('document/EditHistory.ets','EditHistory'),history=new History();
  history.reset('',0);history.record('a',1,1000);history.boundary();history.record('**a**',5,1100);history.boundary();
  assert.equal(history.undo(5).text,'a');
});
test('history is bounded by logical bytes, not just 200 full documents', () => {
  const History=load('document/EditHistory.ets','EditHistory'),history=new History();history.reset('',0);
  for(let i=0;i<30;i++)history.record(i+'x'.repeat(1024*1024),0,1000+i*700);
  assert.ok(history.steps.reduce((sum,x)=>sum+x.text.length*2,0)<=32*1024*1024);
  assert.ok(history.canUndo());
});
test('heading and list shortcuts affect lines rather than words', () => {
  assert.equal(insertEditorAction('hello',2,2,'md-heading','# ','').text,'# hello');
  assert.equal(insertEditorAction('one\ntwo\nthree',0,8,'md-list','- ','').text,'- one\n- two\nthree');
});
test('code block insertion preserves embedded fences and line boundaries', () => {
  assert.equal(insertEditorAction('left```right',4,7,'md-code-block','```\n','\n```').text,'left\n````\n```\n````\nright');
});
test('image alt text is not interpreted as a replacement template', () => {
  usePreviewText({imageSlot:'[%s]'});
  for(const alt of ['$&',"$'",'$`','$$'])assert.equal(imageLabel(alt),`[${alt}]`);
  usePreviewText({});
});
function service(overrides={}) {
  class Info {constructor(){Object.assign(this,{uri:'file://a.md',name:'a.md',newline:'\n',lineEndings:'',encoding:'utf-8',hasBom:false,
    fingerprint:'original',formatId:'markdown',writable:true,persistent:true});}}
  const writes=[],drafts=[];
  const formats={markdown:{id:'markdown',starter:''},plain:{id:'plain',starter:''}};
  const registry={byId:id=>formats[id],byFilename:name=>name.endsWith('.md')?formats.markdown:formats.plain,
    defaultName:f=>f.id==='markdown'?'a.md':'a.txt',resolve:(name,_type,unknown)=>name.endsWith('.md')?formats.markdown:unknown?formats.plain:null};
  const files={prepare:async()=>({writable:true,persistent:true}),chooseSave:async()=> 'file://a.md',read:uri=>({info:Object.assign(new Info(),{uri}),text:'disk'}),
    write:(_info,text,conflict)=>writes.push({text,conflict}),...overrides.files};
  const api=load('document/DocumentService.ets','DocumentService',{DocumentInfo:Info,RecoveryData:Info,copyInfo:x=>Object.assign(new Info(),x),DocumentFiles:files,
    LocalState:{writeDraft:(_ctx,draft)=>drafts.push({...draft}),...overrides.local},FormatRegistry:registry,documentOutline:()=>[],AppText:{text:x=>x},$r:x=>x});
  api.adopt({info:new Info(),text:'base'});api.edit('edited');return{api,writes,drafts};
}
test('save-as to the original URI does not bypass conflict checking', async () => {
  const s=service();await s.api.save({},true);assert.equal(s.writes[0].conflict,true);
});
test('checkpoint failure prevents an external write', async () => {
  const s=service({local:{writeDraft:()=>{throw new Error('disk full')}}});
  await assert.rejects(s.api.save({},false),/disk full/);assert.equal(s.writes.length,0);
});
test('provider write failure leaves complete recovery text', async () => {
  const s=service({files:{write:()=>{throw new Error('partial write')}}});
  await assert.rejects(s.api.save({},false),/partial write/);assert.equal(s.drafts[0].text,'edited');assert.equal(s.drafts[0].savedText,'base');
});
test('opaque file URI is resolved using the provider filename', async () => {
  const s=service();assert.equal(await s.api.openUri('file://12345','',true,true),true);
  assert.equal(s.api.current().info.formatId,'markdown');
});
test('rejected late confirmation does not replace the current session', async () => {
  const s=service(),owner=s.api.current();
  assert.equal(await s.api.openUri('file://b.md','',true,true,async()=>false),false);assert.equal(s.api.current(),owner);
});
