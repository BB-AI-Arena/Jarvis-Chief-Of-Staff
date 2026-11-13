"""Own one checkpointed film worker; recover exits and expose a durable heartbeat."""
import argparse,fcntl,json,os,queue,signal,subprocess,sys,threading,time
from pathlib import Path

MAX_RESTARTS=3
STALL_SECONDS=2700

def atomic(path,value):
    temp=path.with_suffix('.tmp');temp.write_text(json.dumps(value,indent=2));temp.replace(path)

def checkpoint(root):
    try:return json.loads((root/'film-state.json').read_text())
    except (OSError,ValueError):return {}

def retryable(state):
    failure=str(state.get('failure','')).lower()
    return not any(x in failure for x in ('token limit','budget','recovery needs attention','http 401','http 403','invalid api key','different story or configuration'))

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--job',required=True);args=parser.parse_args()
    job=Path(args.job);root=job.parent;lock=(root/'supervisor.lock').open('a')
    try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError:raise SystemExit('Another supervisor already owns this film')
    stop=threading.Event();child=None
    def cancel(*_):
        stop.set()
        if child and child.poll() is None:child.terminate()
    signal.signal(signal.SIGTERM,cancel);signal.signal(signal.SIGINT,cancel)
    marker=root/'supervisor.json'
    prior={}
    try:prior=json.loads(marker.read_text())
    except (OSError,ValueError):pass
    restarts=int(prior.get('restarts',0));last_message=''
    def record(status,**extra):atomic(marker,dict(status=status,restarts=restarts,heartbeat=time.time(),pid=os.getpid(),child_pid=child.pid if child else None,**extra))
    def emit(kind,**extra):print(json.dumps(dict(type=kind,**extra)),flush=True)
    while not stop.is_set():
        record('running')
        child=subprocess.Popen([sys.executable,'-B',str(Path(__file__).with_name('film_worker.py')),'--job',str(job)],stdout=subprocess.PIPE,text=True,bufsize=1)
        events=queue.Queue()
        def read_output(pipe):
            try:
                for line in pipe:events.put(line)
            finally:events.put(None)
        reader=threading.Thread(target=read_output,args=(child.stdout,),daemon=True);reader.start()
        last_activity=time.monotonic();last_heartbeat=0;stalled=False;closed=False
        while not closed:
            try:
                line=events.get(timeout=1)
                if line is None:closed=True;continue
                last_activity=time.monotonic()
                try:event=json.loads(line)
                except ValueError:event={}
                # Native callers see failure only after recovery has been exhausted.
                if event.get('type')=='failed':last_message=event.get('message','Worker failed')
                else:sys.stdout.write(line);sys.stdout.flush()
            except queue.Empty:pass
            if time.monotonic()-last_heartbeat>=15:
                record('cancelling' if stop.is_set() else 'running');last_heartbeat=time.monotonic()
            if stop.is_set() or time.monotonic()-last_activity>STALL_SECONDS:
                stalled=not stop.is_set()
                if child.poll() is None:
                    child.terminate()
                    try:child.wait(timeout=20)
                    except subprocess.TimeoutExpired:child.kill()
        child.wait();child.stdout.close();state=checkpoint(root)
        if stop.is_set():record('cancelled');emit('failed',message='Film stopped by user; checkpoints retained');return 130
        if child.returncode==0 and state.get('completed') and (root/'final.mp4').is_file():record('completed');return 0
        if restarts>=MAX_RESTARTS or not retryable(state):
            message=state.get('failure') or last_message or 'Worker exited before completion'
            record('needs_attention',reason=message);emit('failed',message=message);return 1
        restarts+=1;delay=min(60,10*restarts)
        record('recovering',reason='Worker stalled' if stalled else state.get('failure',last_message),retry_at=time.time()+delay)
        emit('progress',message='Recovering interrupted film worker (%s/%s); saved clips retained'%(restarts,MAX_RESTARTS),phase='recovery',state='rendering')
        if stop.wait(delay):record('cancelled');return 130
    record('cancelled');return 130
if __name__=='__main__':raise SystemExit(main())
