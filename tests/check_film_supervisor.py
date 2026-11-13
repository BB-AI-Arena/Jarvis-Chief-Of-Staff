import importlib.util,json,shutil,subprocess,sys,tempfile,time,unittest
from pathlib import Path
SOURCE=Path(__file__).parents[1]/'Resources/film_supervisor.py'
if not SOURCE.exists():SOURCE=Path('/private/tmp/jarvis-resilience/film_supervisor.py')
spec=importlib.util.spec_from_file_location('supervisor',SOURCE);s=importlib.util.module_from_spec(spec);spec.loader.exec_module(s)
class SupervisorTests(unittest.TestCase):
    def fixture(self,tmp,body):
        root=Path(tmp);shutil.copy2(SOURCE,root/'film_supervisor.py');(root/'film_worker.py').write_text('from pathlib import Path\nimport json,sys,time\nr=Path(__file__).parent\n'+body);(root/'job.json').write_text('{}')
        return root,[sys.executable,'-B',str(root/'film_supervisor.py'),'--job',str(root/'job.json')]
    def test_transient_exit_restarts_without_forwarding_premature_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            root,cmd=self.fixture(tmp,"""n=r/'attempt';attempt=int(n.read_text())+1 if n.exists() else 1;n.write_text(str(attempt))
if attempt==1:
 (r/'film-state.json').write_text(json.dumps({'failure':'HTTP 503 temporary outage'}));print(json.dumps({'type':'failed','message':'temporary outage'}),flush=True);sys.exit(1)
(r/'film-state.json').write_text(json.dumps({'completed':True}));(r/'final.mp4').write_bytes(b'fixture');print(json.dumps({'type':'done','path':str(r/'final.mp4')}),flush=True)
""")
            result=subprocess.run(cmd,capture_output=True,text=True,timeout=25)
            self.assertEqual(result.returncode,0,result.stderr);events=[json.loads(x) for x in result.stdout.splitlines()]
            self.assertNotIn('failed',[x['type'] for x in events]);self.assertIn('done',[x['type'] for x in events])
            self.assertEqual(json.loads((root/'supervisor.json').read_text())['status'],'completed');self.assertEqual((root/'attempt').read_text(),'2')
    def test_budget_exhaustion_escalates_without_restart(self):
        with tempfile.TemporaryDirectory() as tmp:
            root,cmd=self.fixture(tmp,"(r/'film-state.json').write_text(json.dumps({'failure':'Film planning/review token limit reached'}));sys.exit(1)\n")
            result=subprocess.run(cmd,capture_output=True,text=True,timeout=5);state=json.loads((root/'supervisor.json').read_text())
            self.assertEqual(result.returncode,1);self.assertEqual(state['status'],'needs_attention');self.assertEqual(state['restarts'],0)
    def test_user_cancel_never_restarts_and_second_supervisor_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root,cmd=self.fixture(tmp,"(r/'started').write_text('yes');time.sleep(60)\n")
            p=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            try:
                deadline=time.monotonic()+5
                while not (root/'started').exists() and time.monotonic()<deadline:time.sleep(.05)
                self.assertTrue((root/'started').exists())
                duplicate=subprocess.run(cmd,capture_output=True,text=True,timeout=5);self.assertNotEqual(duplicate.returncode,0)
                p.terminate();p.communicate(timeout=5)
                state=json.loads((root/'supervisor.json').read_text());self.assertEqual(state['status'],'cancelled');self.assertEqual(state['restarts'],0)
            finally:
                if p.poll() is None:p.kill();p.communicate()
if __name__=='__main__':unittest.main()
