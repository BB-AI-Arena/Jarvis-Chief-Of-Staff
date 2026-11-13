"""Artwork selection must honor explicit files and stay within the selected directory."""
import importlib.util
from pathlib import Path
import tempfile

spec = importlib.util.spec_from_file_location('artwork', Path(__file__).parents[1] / 'Resources/prepare-video-artwork.py')
artwork = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artwork)
with tempfile.TemporaryDirectory() as tmp:
    base = Path(tmp)
    root = base / 'art'; root.mkdir()
    for name in ['character.png', 'brand-logo.png', 'brand-icon.jpg', '.private.png']:
        (root / name).write_bytes(b'fixture')
    (base / 'outside.png').write_bytes(b'outside')
    (root / 'link.png').symlink_to(base / 'outside.png')
    assert [p.name for p in artwork.select(root, 'Make a branded video')] == ['brand-logo.png', 'brand-icon.jpg', 'character.png']
    assert [p.name for p in artwork.select(root, 'Use CHARACTER.PNG artwork')] == ['character.png']
    for request in ['use missing.png', 'use character.png and missing.png', 'use link.png']:
        try:
            artwork.select(root, request)
        except ValueError:
            pass
        else:
            raise AssertionError('Must reject missing or inaccessible requested artwork: ' + request)
print('PASS: artwork honors explicit filenames, prioritizes brand assets, excludes hidden files and symlinks, and rejects missing references')
