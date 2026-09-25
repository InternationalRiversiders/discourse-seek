const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
function harness() {
  let now=100000, seq=0;
  const timers=new Map();
  const context={Date:class extends Date {static now(){return now;}},Promise,AbortController,DOMException,setTimeout:(fn,ms)=>{const id=++seq;timers.set(id,{fn,at:now+ms});return id;},clearTimeout:id=>timers.delete(id)};
  const source=fs.readFileSync(path.join(__dirname,'../assets/javascripts/discourse/lib/food-request-queue.js'),'utf8').replaceAll('export ','');
  const {RequestQueue,retryDelay}=vm.runInNewContext(source+'\n({RequestQueue,retryDelay})',context);
  const queue=new RequestQueue();
  async function advance(ms){const end=now+ms;for(;;){await new Promise(setImmediate);const next=[...timers].filter(([,t])=>t.at<=end).sort((a,b)=>a[1].at-b[1].at)[0];if(!next){now=end;break;}timers.delete(next[0]);now=next[1].at;next[1].fn();}await new Promise(setImmediate);}
  return {queue,retryDelay,advance,now:()=>now,timers};
}
test('60 image requests respect one shared start budget',async()=>{
 const h=harness(),starts=[];const tasks=Array.from({length:60},()=>h.queue.enqueue(async()=>starts.push(h.now())));
 await h.advance(9999);assert.equal(starts.length,25);await h.advance(15000);await Promise.all(tasks.map(t=>t.promise));assert.equal(starts.length,60);assert(starts.slice(1).every((t,i)=>t-starts[i]>=400));assert.equal(h.timers.size,0);
});
test('quick navigation cancels superseded queued work and prioritizes latest view',async()=>{
 const h=harness(),calls=[];const image=h.queue.enqueue(async()=>calls.push('image'));const old=h.queue.enqueue(async()=>calls.push('old'),{priority:10,delay:200});const cancelled=old.promise.catch(e=>e.name);old.cancel();const latest=h.queue.enqueue(async()=>calls.push('latest'),{priority:10,delay:200});const nextImage=h.queue.enqueue(async()=>calls.push('nextImage'));
 await h.advance(1000);await Promise.all([image.promise,latest.promise,nextImage.promise]);assert.equal(await cancelled,'AbortError');assert.deepEqual(calls,['image','latest','nextImage']);
});
test('cancelling in-flight work signals abort and leaves no queued timer',async()=>{
 const h=harness();let aborted=false;const t=h.queue.enqueue(signal=>new Promise((resolve,reject)=>{signal.addEventListener('abort',()=>{aborted=true;reject(new DOMException('Cancelled','AbortError'));});}));const result=t.promise.catch(e=>e.name);await h.advance(0);t.cancel();await h.advance(1);assert(aborted);assert.equal(await result,'AbortError');assert.equal(h.queue.active,0);assert.equal(h.timers.size,0);
});
test('429 pauses both media and navigation; no immediate retry',async()=>{
 const h=harness(),starts=[];const bad=h.queue.enqueue(async()=>{throw Object.assign(new Error('limit'),{status:429,retryAfter:'2'});});bad.promise.catch(()=>{});const nav=h.queue.enqueue(async()=>starts.push(h.now()),{priority:10,delay:200});await h.advance(1999);assert.equal(starts.length,0);await h.advance(1);await nav.promise;assert.deepEqual(starts,[102000]);
});
test('Retry-After accepts HTTP dates and has a conservative fallback',()=>{
 const h=harness();assert.equal(h.retryDelay({retryAfter:'Thu, 01 Jan 1970 00:01:45 GMT'},100000),5000);assert.equal(h.retryDelay({}),60000);assert.equal(h.retryDelay({getResponseHeader:()=> '0'}),1000);
});
test('image duplicates share work only while mounted and revoke bytes on last release',async()=>{
 const h=harness();let fetches=0,revoked=[];
 const source=fs.readFileSync(path.join(__dirname,'../assets/javascripts/discourse/lib/food-images.js'),'utf8').replace(/^import .*;\n/m,'').replaceAll('export ','');
 const ImageRequests=vm.runInNewContext(source+'\nImageRequests',{foodRequests:h.queue,URL:{createObjectURL:()=> 'blob:test',revokeObjectURL:u=>revoked.push(u)},fetch:async()=>{fetches++;return {ok:true,blob:async()=>({})};},DOMException});
 const images=new ImageRequests(h.queue);const a=images.acquire('/food/media/1'),b=images.acquire('/food/media/1');await h.advance(0);assert.equal(await a.promise,'blob:test');assert.equal(await b.promise,'blob:test');assert.equal(fetches,1);a.release();assert.equal(revoked.length,0);b.release();assert.deepEqual(revoked,['blob:test']);assert.equal(images.entries.size,0);
});
