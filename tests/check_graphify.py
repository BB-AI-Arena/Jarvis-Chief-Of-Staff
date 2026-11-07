"""Exercise the real installed Graphify extractor against a cross-file dependency."""
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='jarvis-graph-test-') as out:
    result = subprocess.run([str(root/'.graphify/bin/graphify'), 'extract', str(root/'tests/fixture'), '--code-only', '--no-cluster', '--max-workers', '2', '--out', out], text=True, capture_output=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
    graph = json.loads((Path(out)/'graphify-out/graph.json').read_text())
    assert any(edge['source'] == 'main' and edge['target'] == 'greeting_greet' and edge['relation'] == 'imports' for edge in graph['edges']), graph
    assert graph.get('input_tokens') == 0 and graph.get('output_tokens') == 0
    print(f"PASS: real Graphify extracted {len(graph['nodes'])} nodes / {len(graph['edges'])} edges, including the cross-file import, with zero model tokens")
