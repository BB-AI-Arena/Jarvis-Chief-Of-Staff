"""Run the native, bounded public-API audio check; credentials never print."""
from pathlib import Path
import subprocess
raise SystemExit(subprocess.call(['/usr/bin/swift', str(Path(__file__).with_suffix('.swift'))]))
