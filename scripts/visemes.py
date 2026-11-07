"""Map model-aligned IPA timings to small, coarticulated facial controls."""
def pose(phoneme):
    p = phoneme.strip('ˈˌːˑ')
    if not p or p in ' .,!?;:—-': return [0, 0, 0, 0]
    if p in 'pbm': return [0, 0, 0, 1]
    if p in 'fv': return [.14, 0, .15, .65]
    if p in 'uʊw': return [.32, 1, 0, 0]
    if p in 'oɔɒ': return [.65, .8, 0, 0]
    if p in 'aɑæʌ': return [.9, 0, .25, 0]
    if p in 'eɛ': return [.55, 0, .8, 0]
    if p in 'iɪj': return [.3, 0, 1, 0]
    if p in 'əɜɚɝ': return [.42, .15, .15, 0]
    if p in 'ʃʒtʧʤ': return [.24, .3, .1, 0]
    return [.22, .05, .15, 0]

def cues(timings):
    return [{'start': round(t.start, 4), 'end': round(t.end, 4), 'pose': pose(t.phoneme)}
            for t in timings if t.end > t.start]
