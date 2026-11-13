"""Job-scoped edit executed on DARK. The GPU encodes picture; CPU mixes sound."""


def finish_script():
    return r'''
import json, subprocess
from pathlib import Path
root = Path(cfg['output']).parent
root.mkdir(parents=True, exist_ok=True)
normalized = []
for i, (file, seconds) in enumerate(zip(cfg['clips'], cfg['durations'])):
    # PCM edit intermediates keep exact cut boundaries across a long film;
    # per-shot AAC priming/padding otherwise accumulates during concat.
    target = root / ('edit-%03d.mov' % (i+1))
    source = Path(file)
    if not source.is_file():
        raise ValueError('Missing rendered clip')
    if not target.exists() or target.stat().st_mtime < source.stat().st_mtime:
        probe = json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-of','json',str(source)]))
        audio = any(s['codec_type'] == 'audio' for s in probe['streams'])
        args = ['ffmpeg','-v','error','-y','-i',str(source)]
        if not audio:
            args += ['-f','lavfi','-i','anullsrc=channel_layout=stereo:sample_rate=48000']
        args += ['-t',str(seconds),'-vf','fps=24:start_time=0,pad=1280:720:(ow-iw)/2:(oh-ih)/2:black,setsar=1',
                 '-af','apad,atrim=duration=%s,asetpts=PTS-STARTPTS,afade=t=in:d=0.06,afade=t=out:st=%.3f:d=0.12' % (seconds,max(0,seconds-0.12)),
                 '-map','0:v:0','-map','0:a:0' if audio else '1:a:0',
                 '-c:v','h264_nvenc','-preset','p6','-cq','18','-pix_fmt','yuv420p','-c:a','pcm_s16le','-ar','48000','-ac','2',str(target)]
        subprocess.run(args,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    normalized.append(target)
listing = root / 'edit-list.txt'
listing.write_text(''.join("file '%s'\n" % str(p).replace("'", "'\\''") for p in normalized))
joined = root / ('joined-' + Path(cfg['output']).stem + '.mov')
subprocess.run(['ffmpeg','-v','error','-y','-f','concat','-safe','0','-i',str(listing),'-c','copy',str(joined)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
seconds = sum(cfg['durations'])
# Preserve quiet scene ambience under coherent narration/score. Normalize the finished mix.
filters = '[0:a]volume=0.22[ambient];[ambient][1:a]amix=inputs=2:duration=first:normalize=0,loudnorm=I=-16:TP=-2.5:LRA=11'
def encode(gain=0):
    chain=filters+(',volume=%.4fdB'%gain if gain else '')+'[audio]'
    subprocess.run(['ffmpeg','-v','error','-y','-i',str(joined),'-i',cfg['sound'],'-filter_complex',chain,
                    '-map','0:v:0','-map','[audio]','-t',str(seconds),'-c:v','copy','-c:a','aac','-b:a','192k','-ar','48000','-ac','2','-movflags','+faststart',cfg['output']],
                   check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
def measure():
    run=subprocess.run(['ffmpeg','-hide_banner','-i',cfg['output'],'-vn','-af','loudnorm=I=-16:TP=-2.5:LRA=11:print_format=json','-f','null','-'],capture_output=True,text=True,check=True)
    text=run.stderr
    return json.loads(text[text.rfind('{'):text.rfind('}')+1])
encode();levels=measure();gain=0
if float(levels['input_tp'])>-1.0:
    # Correct codec overshoot from the uncompressed mix, not by re-encoding AAC.
    gain=-1.8-float(levels['input_tp']);encode(gain);levels=measure()
probe = json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',cfg['output']]))
video = next(s for s in probe['streams'] if s['codec_type']=='video')
audio=next((s for s in probe['streams'] if s['codec_type']=='audio'),None)
if (not (-40 < float(levels['input_i']) < -5) or float(levels['input_tp'])>-1.0
        or not audio or audio['sample_rate']!='48000' or audio['channels']!=2):
    raise ValueError('Finished audio failed loudness, peak-headroom or 48 kHz stereo checks')
print(json.dumps({'duration':probe['format']['duration'],'width':video['width'],'height':video['height'],
                  'audio':any(s['codec_type']=='audio' for s in probe['streams']),'fps':video['r_frame_rate'],'frames':video.get('nb_frames'),
                  'audio_lufs':float(levels['input_i']),'audio_true_peak_db':float(levels['input_tp']), 'encoder':'NVIDIA h264_nvenc',
                  'audio_sample_rate':int(audio['sample_rate']),'audio_channels':audio['channels'],'master_gain_db':gain,
                  'sound':'local Kokoro narration + original score/cues + LTX scene ambience','bytes':Path(cfg['output']).stat().st_size}))
'''
