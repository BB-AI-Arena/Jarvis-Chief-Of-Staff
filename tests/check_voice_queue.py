"""Real British synthesis must retain every queued WAV until playback owns cleanup."""
import json
from pathlib import Path
import select
import subprocess
import wave

root = Path(__file__).resolve().parents[1]
process = subprocess.Popen([str(root/'.voice/bin/python'), str(root/'scripts/voice.py'), '--serve'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
def event():
    assert select.select([process.stdout], [], [], 90)[0], 'Voice worker timed out'
    result = json.loads(process.stdout.readline())
    assert 'error' not in result, result
    return result
try:
    assert event()['ready']
    paths = []
    for i in range(6):
        process.stdin.write(json.dumps({'id':'queue', 'voice':'bm_lewis', 'text':f'This is sentence number {i + 1}.'})+'\n')
        process.stdin.flush()
        result = event()
        assert result['id'] == 'queue' and result['mouthCues']
        paths.append(Path(result['path']))
        for path in paths:
            assert path.exists(), 'Worker deleted audio still awaiting playback'
            with wave.open(str(path)) as audio:
                assert audio.getnframes() > 0
    assert len(set(paths)) == 6
    print('PASS: six British sentence WAVs remain intact while queued for playback')
finally:
    process.stdin.close()
    try: process.wait(timeout=15)
    except subprocess.TimeoutExpired: process.terminate(); process.wait(timeout=5)
