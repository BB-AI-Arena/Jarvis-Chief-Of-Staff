"""Persistent, local-only Kokoro speech worker. One loaded model, stdin JSON jobs."""
import argparse
import json
import os
import re
from pathlib import Path
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from visemes import cues

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / '.voice' / 'models'

def emit(**event):
    print(json.dumps(event), flush=True)

def speech_chunks(text):
    """Start a short natural phrase promptly; preserve every word in bounded chunks."""
    words = text.split()
    chunks, current = [], []
    for word in words:
        limit = 50
        if current and len(' '.join(current + [word])) > limit:
            chunks.append(' '.join(current)); current = []
        current.append(word)
        if re.search(r'[.!?;:,]$', word) and len(' '.join(current)) >= 25:
            chunks.append(' '.join(current)); current = []
    if current: chunks.append(' '.join(current))
    return chunks or ['']

def main():
    os.environ.setdefault('OMP_NUM_THREADS', '2')
    from kokoro_onnx import Kokoro
    import soundfile as sf
    import onnxruntime as ort
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    session = ort.InferenceSession(str(MODEL / 'kokoro-v1.0.onnx'), sess_options=options, providers=['CPUExecutionProvider'])
    kokoro = Kokoro.from_session(session, str(MODEL / 'voices-v1.0.bin'))
    # Warm the inference graph off the conversational path.
    kokoro.create_timed('Ready.', voice='bm_lewis', speed=0.94, lang='en-gb')
    emit(ready=True, voices=kokoro.get_voices())
    output_dir = Path(tempfile.mkdtemp(prefix='jarvis-speech-'))
    try:
        for line in sys.stdin:
            job = {}
            try:
                job = json.loads(line)
                for old in output_dir.glob('*.wav'):
                    old.unlink(missing_ok=True)
                text = str(job['text'])[:2500]
                voice = str(job.get('voice', 'bm_lewis'))
                if voice not in kokoro.get_voices():
                    raise ValueError('Unknown Kokoro voice')
                chunks = speech_chunks(text)
                def render_chunk(item):
                    index, chunk = item
                    start = time.monotonic()
                    samples, rate, timings = kokoro.create_timed(chunk, voice=voice, speed=0.94 if voice == 'bm_lewis' else 1.0, lang='en-gb' if voice.startswith('b') else 'en-us')
                    path = output_dir / f'{time.monotonic_ns()}-{index}.wav'
                    sf.write(path, samples, rate)
                    return dict(id=job.get('id', ''), path=str(path), voice=voice, chunk=index,
                                final=index == len(chunks)-1, mouthCues=cues(timings),
                                seconds=round(time.monotonic()-start, 2), duration=round(len(samples)/rate, 2))
                # Prepare one phrase ahead while the preceding phrase plays. map retains
                # text order even when a later synthesis finishes first.
                with ThreadPoolExecutor(max_workers=2) as pool:
                    for event in pool.map(render_chunk, enumerate(chunks)):
                        emit(**event)

            except Exception as exc:
                emit(id=job.get('id', ''), error=str(exc))
    finally:
        import shutil
        shutil.rmtree(output_dir, ignore_errors=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--serve', action='store_true')
    parser.parse_args()
    try:
        main()
    except Exception as exc:
        emit(error=f'Local speech unavailable: {exc}')
        sys.exit(1)
