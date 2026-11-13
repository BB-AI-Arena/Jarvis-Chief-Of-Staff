"""Read-only provenance audit: Git source -> pre-build manifest -> package -> installed app.

Run after committing the tested source:
python3 tests/check_installed_build.py --ref origin/main --manifest .build/repair-source-manifest.json
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import shutil
import tempfile
import struct


def sha(data):
    return hashlib.sha256(data).hexdigest()


def files(root):
    return {str(p.relative_to(root)): sha(p.read_bytes()) for p in root.rglob('*') if p.is_file()}


def canonical_unsigned_bytes(raw):
    """Normalize only LC_SEGMENT_64 __LINKEDIT VM padding left by codesign removal."""
    data = bytearray(raw)
    assert len(data) >= 32 and struct.unpack_from('<I', data)[0] == 0xfeedfacf, 'Expected thin little-endian Mach-O64'
    cpu = struct.unpack_from('<I', data, 4)[0]
    page = {0x100000c: 16384, 0x1000007: 4096}.get(cpu)
    assert page is not None, 'Unknown Mach-O architecture'
    count, command_bytes = struct.unpack_from('<II', data, 16)
    end = 32 + command_bytes
    assert end <= len(data)
    offset, found = 32, 0
    for _ in range(count):
        assert offset + 8 <= end
        command, size = struct.unpack_from('<II', data, offset)
        assert size >= 8 and offset + size <= end
        assert command != 0x1d, 'Code signature was not removed'
        if command == 0x19 and data[offset+8:offset+24].rstrip(b'\0') == b'__LINKEDIT':
            assert size == 72, 'Unexpected LINKEDIT sections'
            vm_size, file_offset, file_size = struct.unpack_from('<QQQ', data, offset+32)
            assert file_offset + file_size == len(data), 'LINKEDIT must end at EOF'
            assert file_size <= vm_size < file_size + 65536 and vm_size % page == 0, 'Unexpected LINKEDIT VM extent'
            struct.pack_into('<Q', data, offset+32, ((file_size + page - 1) // page) * page)
            found += 1
        offset += size
    assert offset == end and found == 1
    return bytes(data)


def unsigned_sha(binary):
    # Signing legitimately changes Mach-O bytes. Strip only a temporary copy;
    # never mutate the installed app, release artifact or signed package.
    with tempfile.TemporaryDirectory(prefix='jarvis-provenance-') as temporary:
        copy = Path(temporary) / 'Jarvis'
        shutil.copy2(binary, copy)
        subprocess.run(['codesign', '--remove-signature', str(copy)], check=True, capture_output=True)
        return sha(canonical_unsigned_bytes(copy.read_bytes()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ref', default='HEAD')
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--installed', type=Path, default=Path('/Applications/Jarvis.app'))
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    def git(*argv):
        return subprocess.check_output(['git', '-C', str(root), *argv])
    commit = git('rev-parse', '--verify', args.ref + '^{commit}').decode().strip()
    tree = git('rev-parse', commit + '^{tree}').decode().strip()
    manifest = json.loads(args.manifest.read_text())
    expected_paths = {p for p in git('ls-tree', '-r', '--name-only', commit).decode().splitlines()
                      if p == 'Package.swift' or p.startswith(('Sources/', 'Resources/', 'scripts/'))}
    assert set(manifest) == expected_paths, 'Build manifest omits or adds application inputs'
    for path, digest in manifest.items():
        assert sha(git('show', commit + ':' + path)) == digest, 'Published input differs from build: ' + path
        assert sha((root / path).read_bytes()) == digest, 'Working source changed after build: ' + path
    package = root / 'dist/Jarvis.app'
    for app in [package, args.installed]:
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    packaged_files, installed_files = files(package), files(args.installed)
    assert packaged_files == installed_files, 'Installed bundle differs from verified package'
    resources = {p[len('Resources/'):]: digest for p, digest in manifest.items() if p.startswith('Resources/')}
    assert files(args.installed / 'Contents/Resources') == resources, 'Bundled resources contain stale/missing/changed files'
    executable_sha = sha((args.installed / 'Contents/MacOS/Jarvis').read_bytes())
    unsigned_executable_sha = unsigned_sha(args.installed / 'Contents/MacOS/Jarvis')
    assert unsigned_executable_sha == unsigned_sha(root / '.build/release/Jarvis'), 'Installed executable code differs from release build'
    probe = subprocess.run([str(args.installed / 'Contents/MacOS/Jarvis'), '--film-provider-request'],
                           input=json.dumps({'url': 'https://example.invalid/videos', 'body': {}}),
                           capture_output=True, text=True, timeout=10)
    assert probe.returncode == 2 and 'denied' in probe.stdout, 'Installed broker does not reject unsupported endpoint'
    report = {'commit': commit, 'sourceTree': tree, 'sourceManifestSHA256': sha(args.manifest.read_bytes()),
              'verifiedSourceInputs': len(manifest), 'verifiedBundleFiles': len(installed_files),
              'executableSHA256': executable_sha, 'unsignedExecutableSHA256': unsigned_executable_sha,
              'bundleContentSHA256': sha(json.dumps(installed_files, sort_keys=True).encode()),
              'strictCodeSignature': True, 'resourcesExactlyMatchSource': True,
              'installedEqualsPackage': True, 'brokerRejectsUnsupportedEndpoint': True}
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
