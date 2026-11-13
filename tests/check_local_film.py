"""Local production routing and network refusal without credentials or network."""
import importlib.util
from pathlib import Path
import tempfile
import os
from unittest.mock import patch
root=Path(__file__).resolve().parents[1]
s=importlib.util.spec_from_file_location('film_worker',root/'Resources/film_worker.py');w=importlib.util.module_from_spec(s);s.loader.exec_module(w)
with patch.dict(os.environ,{'JARVIS_LOCAL_FILM_ONLY':'1','JARVIS_FILM_LOCAL_HOST':'192.168.4.31'}):
    with patch.object(w.urllib.request,'urlopen') as net,patch.object(w.subprocess,'run') as broker:
        for url in ['https://api.anthropic.com/v1/messages','https://api.x.ai/v1/images/edits','https://example.com']:
            try:w.http(url)
            except RuntimeError as e:assert 'refused' in str(e)
            else:raise AssertionError('external request allowed')
        net.assert_not_called();broker.assert_not_called()
with tempfile.TemporaryDirectory() as tmp,patch.object(w.Film,'preview_ref',return_value=[]):
    spec={'server':'http://192.168.4.31:8188','client_id':'fixture','seconds':5,'brief':'fixture','director_system':'JSON','artwork':[],'local_production':True}
    film=w.Film(spec,tmp)
    requests=[]
    def api(url,body=None,**kwargs):
        requests.append((url,body,kwargs))
        if url.endswith('/queue'):return {'queue_running':[],'queue_pending':[]}
        if url.endswith('/free'):return b''
        return {'done':True,'message':{'content':'{"ready":true}'}}
    with patch.object(w,'http',side_effect=api):
        assert film.claude('Plan',blocks=[{'type':'image','source':{'type':'base64','data':'fixture'}}])=={'ready':True}
    assert all('192.168.4.31' in x[0] for x in requests)
    body=requests[-1][1]
    assert body['keep_alive']==0 and body['format']=='json' and body['messages'][1]['images']==['fixture']
    assert requests[1][2].get('binary') is True,'Empty Comfy free response must not be parsed as JSON'
    with patch.object(w,'http',return_value={'done':False,'message':{'content':'{}'}}):
        try:film.local_director('Plan',[],'JSON',50)
        except ValueError as e:assert 'incomplete' in str(e)
        else:raise AssertionError('incomplete local response accepted')
print('PASS: local-only film blocks providers, preserves vision payload, releases idle models and rejects incomplete replies')
