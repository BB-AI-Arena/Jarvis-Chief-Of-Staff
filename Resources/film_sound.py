"""Offline narration, restrained original score and cues. No voice or music API."""
import hashlib
import json
import math
from pathlib import Path
import os


def create_sound(plan, root, project, count, stop):
    import numpy as np
    import soundfile as sf
    import onnxruntime as ort
    from kokoro_onnx import Kokoro
    root, project = Path(root), Path(project)
    shots = plan['shots'][:count]
    rate = 48000
    duration = sum(s['seconds'] for s in shots)
    target = root / ('sound-%s.wav' % count)
    generated=root/'generated-score.wav'
    generated_hash=''
    if generated.is_file():
        with generated.open('rb') as source:generated_hash=hashlib.file_digest(source,'sha256').hexdigest()
    stamp = hashlib.sha256(('score-v3|'+generated_hash+'|' + json.dumps(shots, sort_keys=True)).encode()).hexdigest()
    sidecar = target.with_suffix('.json')
    if target.exists() and sidecar.exists() and json.loads(sidecar.read_text()).get('signature') == stamp:
        return target
    speech = root / 'speech'
    speech.mkdir(exist_ok=True)
    os.environ.setdefault('OMP_NUM_THREADS', '2')
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    session = ort.InferenceSession(str(project / '.voice/models/kokoro-v1.0.onnx'), sess_options=options, providers=['CPUExecutionProvider'])
    voice = Kokoro.from_session(session, str(project / '.voice/models/voices-v1.0.bin'))
    # Original restrained underscore: soft harmonic pads, sparse motif and an evolving pulse.
    # Dynamics follow a six-act arc, so a long story does not repeat an identical sound loop.
    music = np.zeros(int(duration*rate), dtype=np.float32)
    rng = np.random.default_rng(4090)
    for bar in range(math.ceil(duration/4)):
        if stop.is_set():
            raise InterruptedError('Sound preparation stopped')
        start = int(bar*4*rate)
        n = min(int(4*rate), len(music)-start)
        if n <= 0:
            break
        position = bar*4/max(duration,1)
        tension = [0.25,0.42,0.72,0.22,0.64,0.16][min(5,int(position*6))]
        base = [110.0,87.307,97.999,82.407][(bar//4)%4]
        t = np.arange(n,dtype=np.float32)/rate
        envelope = np.minimum(t/1.2,1)*np.minimum((4-t)/1.3,1)
        pad = np.zeros(n,dtype=np.float32)
        for ratio in [1,1.1892,1.4983,2]:
            f=base*ratio
            # Gentle detuning and soft upper partials add depth without harsh synthesized brass.
            pad += (np.sin(2*np.pi*f*t)+0.28*np.sin(2*np.pi*f*1.002*t)+0.12*np.sin(2*np.pi*2*f*t))/5.6
        music[start:start+n] += ((0.013+0.009*tension)*pad*envelope).astype(np.float32)
        for beat in range(4):
            pos=start+beat*rate
            m=min(rate//3,len(music)-pos)
            if m>0:
                tt=np.arange(m,dtype=np.float32)/rate
                pulse=np.sin(2*np.pi*55*tt)*np.exp(-tt*16)
                air=rng.normal(0,1,m).astype(np.float32)*np.exp(-tt*45)
                music[pos:pos+m] += ((0.008+0.018*tension)*pulse+0.0015*tension*air).astype(np.float32)
        if bar%2==0:
            m=min(2*rate,len(music)-start)
            tt=np.arange(m,dtype=np.float32)/rate
            f=220*2**([0,7,10,7,3,7,12,10][(bar//2)%8]/12)
            motif=(np.sin(2*np.pi*f*tt)+0.22*np.sin(2*np.pi*f*2*tt))*np.exp(-tt*2.2)*np.minimum(tt/0.015,1)
            music[start:start+m] += (0.011*motif).astype(np.float32)
    if generated_hash:
        score,sr=sf.read(generated,dtype='float32',always_2d=True)
        if sr!=rate or len(score)<duration*rate or not np.isfinite(score).all():
            raise ValueError('Generated score must contain the complete film at 48 kHz')
        mix=score[:duration*rate,:2].copy()
        rms=float(np.sqrt(np.mean(mix*mix)))
        if rms<.0001:raise ValueError('Generated score is silent')
        mix*=.032/rms
    else:mix = music
    captions = []
    cursor = 0.0
    measurements = []
    for i, shot in enumerate(shots):
        if stop.is_set():
            raise InterruptedError('Sound preparation stopped')
        text = shot.get('narration', '').strip()
        if text:
            key = hashlib.sha256(('bm_lewis|1.02|' + text).encode()).hexdigest()
            file = speech / (key + '.wav')
            if not file.exists():
                samples, sample_rate = voice.create(text, voice='bm_lewis', speed=1.02, lang='en-gb')
                sf.write(file, samples, sample_rate)
            samples, sample_rate = sf.read(file, dtype='float32')
            if samples.ndim > 1:
                samples = samples.mean(axis=1)
            # Disallow rushed, cut-off narration rather than silently truncating words.
            length = len(samples)/sample_rate
            if length > shot['seconds']-0.15:
                raise ValueError('Narration for shot %s runs %.2fs in a %ss shot; shorten it in the saved plan' % (i+1, length, shot['seconds']))
            resampled = np.interp(np.arange(int(length*rate))/rate, np.arange(len(samples))/sample_rate, samples).astype(np.float32)
            peak = float(np.max(np.abs(resampled))) if len(resampled) else 0
            if peak > 0:
                resampled *= 0.62/peak
            begin = int((cursor+0.1)*rate)
            end = min(begin+len(resampled), len(mix))
            if generated_hash:
                # Duck the instrumental under the voice without flattening its wider story arc.
                attack=min(int(.08*rate),begin);release=min(int(.32*rate),len(mix)-end)
                mix[begin-attack:begin] *= np.linspace(1,.42,attack,dtype='float32')[:,None]
                mix[begin:end] *= .42
                mix[end:end+release] *= np.linspace(.42,1,release,dtype='float32')[:,None]
                mix[begin:end] += resampled[:end-begin,None]
            else:mix[begin:end] += resampled[:end-begin]
            captions.append((cursor+0.1, cursor+0.1+length, text))
            measurements.append({'shot': i+1, 'text': text, 'seconds': length})
        cue = shot.get('sound_cue', 'none')
        if cue in ['phone', 'reveal', 'resolve']:
            begin = int((cursor+shot['seconds']*0.6)*rate)
            n = min(int(0.7*rate), len(mix)-begin)
            t = np.arange(n)/rate
            freq = 880 if cue == 'phone' else 660 if cue == 'reveal' else 440
            chime = 0.045*(np.sin(2*np.pi*freq*t)+0.5*np.sin(2*np.pi*freq*1.5*t))*np.exp(-t*7)
            mix[begin:begin+n] += chime.astype(np.float32)[:,None] if generated_hash else chime.astype(np.float32)
        cursor += shot['seconds']
    # Gentle opening/ending fades and deterministic peak limiting.
    n = min(rate, len(mix)//2)
    fade=np.linspace(0,1,n)
    mix[:n] *= fade[:,None] if generated_hash else fade
    mix[-n:] *= fade[::-1,None] if generated_hash else fade[::-1]
    peak = float(np.max(np.abs(mix)))
    if peak > 0.9:
        mix *= 0.9/peak
    sf.write(target, mix, rate, subtype='PCM_16')
    sidecar.write_text(json.dumps({'signature': stamp, 'duration': duration, 'voice': 'bm_lewis', 'narration': measurements, 'score_sha256':generated_hash,'sound': ('DARK ACE-Step 1.5 original instrumental score, ducked under local narration, with original cues' if generated_hash else 'original evolving harmonic underscore, sparse motif, brief original cues and local narration')}, indent=2))
    def timestamp(value):
        ms = int(round(value*1000))
        return '%02d:%02d:%02d,%03d' % (ms//3600000, ms//60000 % 60, ms//1000 % 60, ms % 1000)
    (root / ('captions-%s.srt' % count)).write_text('\n\n'.join('%s\n%s --> %s\n%s' % (i+1, timestamp(a), timestamp(b), text) for i, (a,b,text) in enumerate(captions)) + '\n')
    return target
