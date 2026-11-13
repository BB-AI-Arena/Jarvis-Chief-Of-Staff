"""Exercise the real local British worker: one complete WAV per spoken reply."""
import json
from pathlib import Path
import select
import subprocess
import wave

root = Path(__file__).resolve().parents[1]
p = subprocess.Popen([str(root/'.voice/bin/python'), str(root/'scripts/voice.py'), '--serve'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
def event():
    assert select.select([p.stdout], [], [], 90)[0], 'Speech worker timed out'
    value = json.loads(p.stdout.readline())
    assert 'error' not in value, value
    return value
try:
    assert event()['ready']
    p.stdin.write(json.dumps({'id':'continuity', 'text':'Certainly, Brandon. I will keep the screenplay safe while the directors finish their review.', 'voice':'bm_lewis'})+'\n'); p.stdin.flush()
    result = event()
    assert result['id'] == 'continuity' and result['voice'] == 'bm_lewis'
    assert result['duration'] > 4 and result['mouthCues']
    with wave.open(result['path']) as audio:
        assert audio.getnframes() > audio.getframerate()*4
    assert not select.select([p.stdout], [], [], 1)[0], 'Reply was split into multiple playback events'
    print('PASS: British Lewis returns one continuous WAV with mouth timings', result['duration'])
finally:
    p.stdin.close(); p.wait(timeout=15)
