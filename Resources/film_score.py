"""Optional original instrumental scoring through DARK's native ACE-Step 1.5 nodes."""
import hashlib
import json
import math
from pathlib import Path

MODEL = 'ace_step_1.5_turbo_aio.safetensors'


def score_graph(tags, seconds, bpm, key, seed, prefix):
    return {
        'model': {'class_type':'CheckpointLoaderSimple','inputs':{'ckpt_name':MODEL}},
        'shift': {'class_type':'ModelSamplingAuraFlow','inputs':{'model':['model',0],'shift':3.0}},
        'text': {'class_type':'TextEncodeAceStepAudio1.5','inputs':{
            'clip':['model',1],'tags':tags+' Instrumental only, no vocals, speech or choir.',
            'lyrics':'[Instrumental]','seed':seed,'bpm':bpm,'duration':seconds,
            'timesignature':'4','language':'en','keyscale':key,'generate_audio_codes':True,
            'cfg_scale':2.0,'temperature':.85,'top_p':.9,'top_k':0,'min_p':0.0}},
        'negative': {'class_type':'ConditioningZeroOut','inputs':{'conditioning':['text',0]}},
        'latent': {'class_type':'EmptyAceStep1.5LatentAudio','inputs':{'seconds':seconds,'batch_size':1}},
        'sample': {'class_type':'KSampler','inputs':{'model':['shift',0],'positive':['text',0],
            'negative':['negative',0],'latent_image':['latent',0],'seed':seed,'steps':8,'cfg':1.0,
            'sampler_name':'euler','scheduler':'simple','denoise':1.0}},
        'decode': {'class_type':'VAEDecodeAudio','inputs':{'samples':['sample',0],'vae':['model',2]}},
        'save': {'class_type':'SaveAudio','inputs':{'audio':['decode',0],'filename_prefix':prefix}},
    }


def file_hash(file):
    with Path(file).open('rb') as source:
        return hashlib.file_digest(source,'sha256').hexdigest()


def prepare_score(film, plan, info):
    def digest(value):return hashlib.sha256(json.dumps(value,sort_keys=True,ensure_ascii=False).encode()).hexdigest()
    def atomic(path,value):
        tmp=path.with_name(path.name+'.tmp');tmp.write_text(json.dumps(value,indent=2,ensure_ascii=False));tmp.replace(path)
    names=info.get('CheckpointLoaderSimple',{}).get('input',{}).get('required',{}).get('ckpt_name',[[]])[0]
    if MODEL not in names or any(n not in info for n in ['TextEncodeAceStepAudio1.5','EmptyAceStep1.5LatentAudio','VAEDecodeAudio','SaveAudio']):
        film.progress('Using the local synthesized underscore; ACE-Step music model is not installed','sound')
        return None
    import numpy as np
    import soundfile as sf
    total=film.spec['seconds'];root=film.root;rate=48000
    screenplay=root/'screenplay.json'
    events=[{'start':p['start'],'end':p['end'],'event':p['event']} for p in json.loads(screenplay.read_text()).get('segments',[])] if screenplay.exists() else [{'event':plan['concept']}]
    signature=digest([film.spec['brief'],plan['title'],events,total,MODEL,'instrumental-score-v1'])
    state=film.state.get('score',{})
    target=root/'generated-score.wav';meta=root/'generated-score.json'
    if state.get('signature')==signature and state.get('sha256') and target.is_file() and file_hash(target)==state['sha256']:
        return target
    count=max(1,math.ceil(total/210));overlap=6 if count>1 else 0
    seconds=max(10,(total+overlap*(count-1))/count)
    if state.get('signature')!=signature:
        film.progress('Creative is composing a continuous instrumental score for the story','sound')
        direction=film.claude('Compose an ORIGINAL instrumental film-score brief for the story timeline. No artist/composer imitation, lyrics, vocals, speech or choir. '
            'Choose one coherent instrumental palette, tempo, key and short recurring melodic motif, with emotional development matching the events. '
            'Leave space for narration and natural scene sound; avoid constant trailer impacts or identical repeated loops. '
            'Write %s cue descriptions, each covering roughly %ss of story, with %ss musical overlaps. Repeat the shared palette/motif in each tags string, then describe that section\'s dramatic development and ending. '
            'Return {"bpm":76,"key":"D minor","cues":[{"tags":"detailed positive musical direction"}]}. Use a supported key and bpm 45–150.\nUSER STORY: '%(count,round(seconds,2),overlap)+film.spec['brief']+'\nTIMELINE: '+json.dumps(events),maximum=1900)
        keys=info['TextEncodeAceStepAudio1.5']['input']['required']['keyscale'][1]['options']
        if (type(direction.get('bpm')) is not int or not 45<=direction['bpm']<=150 or direction.get('key') not in keys
                or len(direction.get('cues',[]))!=count or any(not isinstance(c.get('tags'),str) or len(c['tags'])<80 for c in direction['cues'])):
            raise ValueError('Invalid local music direction')
        state={'signature':signature,'plan':direction,'cues':{}}
        film.state['score']=state;film.save()
    direction=state['plan'];tracks=[]
    for i,cue in enumerate(direction['cues']):
        file=root/('score-cue-%03d.flac'%(i+1));old=state['cues'].get(str(i),{})
        if not old.get('sha256') or not file.is_file() or file_hash(file)!=old['sha256']:
            film.progress('Composing instrumental score %s/%s on the 4090'%(i+1,count),'sound',i)
            graph=score_graph(cue['tags'],seconds,direction['bpm'],direction['key'],int(signature[:8],16)+i,'jarvis-films/%s/score-%03d'%(film.client,i+1))
            atomic(root/('score-cue-%03d-graph.json'%(i+1)),graph)
            output,prompt_id=film.comfy(graph,'music',i,timeout=1200)
            data=film.view(output);file.write_bytes(data)
            state['cues'][str(i)]={'output':output,'prompt_id':prompt_id,'sha256':hashlib.sha256(data).hexdigest()};film.save()
        audio,sr=sf.read(file,dtype='float32',always_2d=True)
        if len(audio)/sr<seconds-.15 or not np.isfinite(audio).all() or float(np.sqrt(np.mean(audio*audio)))<.0001:
            raise ValueError('Local score cue is too short, silent or invalid')
        if audio.shape[1]==1:audio=np.repeat(audio,2,axis=1)
        else:audio=audio[:,:2]
        n=round(seconds*rate)
        if sr!=rate:
            t=np.arange(n)/rate
            audio=np.stack([np.interp(t,np.arange(len(audio))/sr,audio[:,c]) for c in range(2)],axis=1).astype('float32')
        audio=audio[:n]
        if len(audio)<n:audio=np.pad(audio,((0,n-len(audio)),(0,0)))
        tracks.append(audio)
    mix=tracks[0]
    for track in tracks[1:]:
        n=overlap*rate;fade=np.linspace(0,1,n,dtype='float32')[:,None]
        mix=np.concatenate([mix[:-n],mix[-n:]*(1-fade)+track[:n]*fade,track[n:]])
    mix=mix[:total*rate]
    if len(mix)<total*rate:mix=np.pad(mix,((0,total*rate-len(mix)),(0,0)))
    tmp=target.with_name('generated-score-pending.wav');sf.write(tmp,mix,rate,subtype='PCM_16');tmp.replace(target)
    state.update(sha256=file_hash(target),seconds=total,sample_rate=rate,channels=2,model=MODEL,overlap_seconds=overlap)
    atomic(meta,state);film.save()
    film.progress('Original 4090 instrumental score ready; mixing local narration and scene sound','sound')
    return target
