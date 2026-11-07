"""Persistent, local-only Kokoro speech worker. One loaded model, stdin JSON jobs."""
import argparse
import json
import os
from pathlib import Path
import sys
import tempfile
import time
from visemes import cues

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / '.voice' / 'models'

def emit(**event):
    print(json.dumps(event), flush=True)

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
    emit(ready=True, voices=kokoro.get_voices())
    output_dir = Path(tempfile.mkdtemp(prefix='jarvis-speech-'))
    try:
        for line in sys.stdin:
            job = {}
            try:
                job = json.loads(line)
                text = str(job['text'])[:2500]
                voice = str(job.get('voice', 'bm_lewis'))
                if voice not in kokoro.get_voices():
                    raise ValueError('Unknown Kokoro voice')
                start = time.monotonic()
                samples, rate, timings = kokoro.create_timed(text, voice=voice, speed=1.0, lang='en-gb' if voice.startswith('b') else 'en-us')
                path = output_dir / f'{time.monotonic_ns()}.wav'
                sf.write(path, samples, rate)
                for old in sorted(output_dir.glob('*.wav'))[:-4]:
                    old.unlink(missing_ok=True)
                emit(id=job.get('id', ''), path=str(path), voice=voice, mouthCues=cues(timings), seconds=round(time.monotonic()-start, 2), duration=round(len(samples)/rate, 2))
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
