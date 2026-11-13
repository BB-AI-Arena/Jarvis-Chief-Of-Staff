"""Paid worker calls must use the native broker, including after supervisor restart."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
spec = importlib.util.spec_from_file_location('film_worker', Path(__file__).resolve().parents[1] / 'Resources/film_worker.py')
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
class BrokerTests(unittest.TestCase):
    def test_missing_broker_never_sends(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(w.urllib.request, 'urlopen') as network:
            with self.assertRaisesRegex(RuntimeError, 'unavailable'):
                w.http('https://api.anthropic.com/v1/messages', {'model':'fixture'})
            network.assert_not_called()
    def test_broker_gets_payload_but_never_credentials(self):
        with tempfile.NamedTemporaryFile() as broker:
            os.chmod(broker.name, 0o700)
            with patch.dict(os.environ, {'JARVIS_FILM_BUDGET_BROKER':broker.name}), patch.object(w.subprocess, 'run', return_value=subprocess.CompletedProcess([],0,b'{"ok":true}',b'')) as run, patch.object(w.urllib.request,'urlopen') as network:
                self.assertEqual(w.http('https://api.x.ai/v1/images/edits', {'n':1}, {'Authorization':'secret-fixture'}),{'ok':True})
                packet=json.loads(run.call_args.kwargs['input']);self.assertEqual(set(packet),{'url','body'})
                self.assertNotIn(b'secret-fixture',run.call_args.kwargs['input']);network.assert_not_called()
    def test_denial_retains_failure_instead_of_direct_fallback(self):
        with tempfile.NamedTemporaryFile() as broker:
            os.chmod(broker.name,0o700)
            with patch.dict(os.environ,{'JARVIS_FILM_BUDGET_BROKER':broker.name}),patch.object(w.subprocess,'run',return_value=subprocess.CompletedProcess([],3,b'{}',b'')),patch.object(w.urllib.request,'urlopen') as network:
                with self.assertRaisesRegex(RuntimeError,'checkpoint retained'):
                    w.http('https://api.anthropic.com/v1/messages',{})
                network.assert_not_called()
if __name__=='__main__':unittest.main()
