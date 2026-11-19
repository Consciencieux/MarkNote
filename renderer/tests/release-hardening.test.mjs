import test from 'node:test';
import assert from 'node:assert/strict';
import { loadArkts } from './helpers/arkts-loader.mjs';
import { insertEditorAction } from '../../entry/src/main/ets/document/EditorActions.ts';
import { imageLabel, usePreviewText } from '../src/preview-text.ts';

function load(relative, exported, context = {}) {
  return loadArkts(relative, exported, context);
}
const wantConstant = { Params: { PARAMS_STREAM: 'stream' },
  Flags: { FLAG_AUTH_READ_URI_PERMISSION: 1, FLAG_AUTH_WRITE_URI_PERMISSION: 2 } };
test('known notices stay visible and other errors stay hidden', () => {
  const api = load('document/UserNotice.ets', '({ userNotice, userNoticeMessage })');
  assert.equal(api.userNoticeMessage(api.userNotice('too large')), 'too large');
  assert.equal(api.userNoticeMessage(new Error('code 13900001 at /data/storage')), '');
});
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
