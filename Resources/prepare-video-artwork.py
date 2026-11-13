"""Run on DARK: import explicitly configured artwork into ComfyUI without changing source files."""
import hashlib
import io
import json
import re
from pathlib import Path
import sys
import urllib.request
import uuid


def select(root, brief):
    root = root.resolve(strict=True)
    candidates = []
    for path in sorted(root.rglob('*')):
        if any(part.startswith('.') for part in path.relative_to(root).parts):
            continue
        if path.is_symlink() or root not in path.resolve().parents:
            continue
        if path.suffix.lower() not in ('.png', '.jpg', '.jpeg', '.webp') or not path.is_file():
            continue
        if path.stat().st_size > 20_000_000:
            continue
        candidates.append(path)
        if len(candidates) >= 200:
            break
    requested = set(re.findall(r'[\w.-]+\.(?:png|jpe?g|webp)\b', brief.lower()))
    named = [p for p in candidates if p.name.lower() in requested]
    missing = requested - {p.name.lower() for p in named}
    if missing:
        raise ValueError('Requested artwork not found: ' + ', '.join(sorted(missing)))
    # Brand assets first; stable order so the manifest records reproducible choices.
    chosen = named or sorted(candidates, key=lambda p: (0 if 'logo' in p.stem.lower() else 1 if 'icon' in p.stem.lower() else 2, str(p)))
    return chosen[:12]


def prepare(directory, brief, server, width, height):
    from PIL import Image, ImageOps
    width, height = int(width), int(height)
    output = []
    for path in select(Path(directory), brief):
        data = path.read_bytes()
        with Image.open(io.BytesIO(data)) as image:
            image = ImageOps.exif_transpose(image).convert('RGBA')
            fitted = ImageOps.contain(image, (width, height), Image.Resampling.LANCZOS)
            canvas = Image.new('RGB', (width, height), 'black')
            canvas.paste(fitted, ((width - fitted.width) // 2, (height - fitted.height) // 2), fitted)
            encoded = io.BytesIO()
            canvas.save(encoded, format='PNG')
            prepared = encoded.getvalue()
        digest = hashlib.sha256(data).hexdigest()
        name = f'jarvis-artwork-{digest}-{width}x{height}.png'
        boundary = 'jarvis-' + uuid.uuid4().hex
        body = (f'--{boundary}\r\nContent-Disposition: form-data; name="image"; filename="{name}"\r\nContent-Type: application/octet-stream\r\n\r\n'.encode()
                + prepared + f'\r\n--{boundary}--\r\n'.encode())
        request = urllib.request.Request(server.rstrip('/') + '/upload/image', data=body,
                                         headers={'Content-Type': 'multipart/form-data; boundary=' + boundary})
        with urllib.request.urlopen(request, timeout=20) as response:
            result = json.load(response)
        uploaded = '/'.join(filter(None, [result.get('subfolder', ''), result['name']]))
        output.append({'source': str(path), 'sha256': digest, 'image': uploaded})
    return output


if __name__ == '__main__':
    print(json.dumps(prepare(*sys.argv[1:])))
