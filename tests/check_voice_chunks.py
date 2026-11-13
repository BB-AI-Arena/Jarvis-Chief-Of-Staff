import json, subprocess,sys,time
from pathlib import Path
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'scripts'))
from voice import speech_chunks
for text in ['At your service. The screenplay is saved, and I shall bring you the complete version once the directors agree.','The collector examines the exact edition and sends an offer. '*30,'','Ready.']:
 parts=speech_chunks(text);assert ' '.join(parts)==' '.join(text.split());assert all(len(x)<=50 for x in parts)
assert len(speech_chunks('At your service. I have your screenplay ready for review.')[0]) <= 50
print('PASS: complete text preserved across bounded voice chunks, opening phrase bounded without discarding words',flush=True)
p=subprocess.Popen([str(root/'.voice/bin/python'),str(root/'scripts/voice.py'),'--serve'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
start=time.monotonic();assert json.loads(p.stdout.readline()).get('ready');print('Warm ready seconds',round(time.monotonic()-start,2),flush=True)
try:
 for i in range(2):
  p.stdin.write(json.dumps({'id':str(i),'voice':'bm_lewis','text':'At your service. The screenplay is saved, and I shall bring you the complete version once the directors agree.'})+'\n');p.stdin.flush();start=time.monotonic();rows=[]
  while True:
   event=json.loads(p.stdout.readline());assert 'error' not in event,event
   assert event['id']==str(i) and event['voice']=='bm_lewis' and Path(event['path']).stat().st_size>44
   rows.append(event)
   print('chunk',event['chunk'],'ready',round(time.monotonic()-start,2),'duration',event['duration'],flush=True)
   if len(rows)==1:print('British first audio seconds',round(time.monotonic()-start,2),flush=True)
   if event.get('final'):break
  assert [r['chunk'] for r in rows]==list(range(len(rows)))
  assert sum(bool(r['final']) for r in rows)==1
  print('PASS: real British PCM chunks ordered with exactly one final marker',flush=True)
finally:p.stdin.close();p.wait(timeout=10)
