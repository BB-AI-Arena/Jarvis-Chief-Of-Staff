"""Exercise the installed local model with the app's actual router instructions."""
import json, pathlib, re, time, urllib.request
source = (pathlib.Path(__file__).parents[1] / 'Sources/Jarvis/AppVoice.swift').read_text()
system = json.loads('"' + re.search(r'\+ "(You are Jarvis,.*?)(?<!\\)"', source).group(1) + '"')
schema = {'type': 'object', 'properties': {'route': {'type': 'string', 'enum': ['reply', 'astra', 'task']}, 'text': {'type': 'string'}}, 'required': ['route', 'text'], 'additionalProperties': False}
for prompt, route in [
    ('Hello Jarvis. Are you ready? One short sentence.', 'reply'),
    ('We might add a calendar feature someday. What do you think?', 'reply'),
    ('Ask Astra to evaluate a distributed event log for our agent office.', 'astra'),
    ('Inspect your own Jarvis source and report which file implements speech playback. Execute this inspection now.', 'task'),
]:
    payload = {'model': 'gemma4:latest', 'stream': False, 'think': False, 'keep_alive': '30m', 'format': schema, 'messages': [{'role': 'system', 'content': system}, {'role': 'user', 'content': prompt}], 'options': {'num_predict': 600, 'num_ctx': 8192, 'temperature': 0}}
    started = time.monotonic()
    result = json.load(urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:11434/api/chat', data=json.dumps(payload).encode(), headers={'Content-Type': 'application/json'}), timeout=90))
    text = result['message']['content'].strip()
    if text.startswith('```json\n') and text.endswith('```'): text = text[8:-3].strip()
    answer = json.loads(text)
    assert answer['route'] == route and answer['text'].strip(), answer
    print(f'PASS: local {route} routing in {time.monotonic()-started:.2f}s', flush=True)
