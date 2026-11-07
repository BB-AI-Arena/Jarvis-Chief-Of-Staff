"""Verify real Lewis/worker synthesis and warm process reuse; no audio playback."""
import json
from pathlib import Path
import selectors
import subprocess
import sys
import time
import soundfile as sf

root = Path(__file__).resolve().parents[1]
process = subprocess.Popen([sys.executable, str(root/'scripts/voice.py'), '--serve'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
def event(timeout=55):
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    assert selector.select(timeout), 'Speech worker did not respond'
    selector.close()
    line = process.stdout.readline()
    assert line, f'Speech worker exited: {process.poll()}'
    data = json.loads(line)
    assert 'error' not in data, data
    return data
try:
    ready = event()
    assert ready['ready'] and 'bm_lewis' in ready['voices'] and 'bf_emma' in ready['voices']
    for voice in ['bm_lewis', 'bf_emma']:
        process.stdin.write(json.dumps({'voice': voice, 'text': 'Good evening. Ready for the next assignment.'})+'\n')
        process.stdin.flush()
        data = event()
        samples, rate = sf.read(data['path'])
        assert data['mouthCues'] and any(c['pose'][0] > .5 for c in data['mouthCues']), 'Missing real timed vowel shapes'
        assert all(0 <= c['start'] < c['end'] <= len(samples)/rate+.02 for c in data['mouthCues']), 'Mouth timings outside playback'
        assert rate == 24000 and len(samples) > rate and max(abs(samples)) > .01, data
        print(f"PASS: {voice}, {len(samples)/rate:.2f}s audio, {data['seconds']}s synthesis, one persistent worker")
finally:
    process.stdin.close()
    try: process.wait(timeout=10)
    except subprocess.TimeoutExpired: process.terminate()
