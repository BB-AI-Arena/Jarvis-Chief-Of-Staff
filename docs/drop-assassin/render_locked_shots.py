#!/usr/bin/env python3
"""Print one ComfyUI API request for a locked Drop Assassin shot.

Usage: python3 docs/drop-assassin/render_locked_shots.py 1 > /tmp/shot-1.json
The request is intended for the existing LTX 2.3 workflow on DARK.
"""

import copy
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / "tests/video/ltx-workflow.json"
LOCK = """Drop Assassin, the same hooded figure in every shot. Matte-black double-breasted tactical longcoat to the ankles, hood up, high collar. One solid horizontal crimson visor band across the eyes, opaque, no visible eyes. Fair lower face, small nose, closed mouth, no beard, jaw in shadow. Thin silver filament seams along the shoulder seams and outer sleeves. Black gloves, black combat boots. A compact carbon drop-rig of two folded fins on the upper back, carbon weave, silver leading edges. High-contrast cinematic grade, crushed blacks, teal night fill, hard magenta rim light on the hood edge and coat rim only, the coat stays matte black, wet highlights. No on-screen text, HD."""
NEGATIVE = """blurry, low quality, distorted, deformed, watermark, text artifacts, pc game, video game, cartoon, ugly, bare face, visible eyes, two eye slits, full face mask, white chest emblem, six wings, spider wings, chest glider, red suit, beard, smile, teeth, different person"""
ACTIONS = {
    1: "He dives headfirst from the rain-soaked rooftop into free fall; the longcoat snaps in the wind and the same two carbon fins begin to open. Keep the same face, costume, and visor. Cyan bounce #12B3B7 and magenta rim #E22D83 stay in narrow edge highlights; broad coat panels remain #130B07, never magenta.",
    2: "He flies between glass towers in a rainy night canyon; the same two fins open as two blades with silver edges, one gloved hand cuts the rain. Keep the same face, costume, and visor. Cyan bounce #12B3B7 and magenta rim #E22D83 stay in narrow edge highlights; broad coat panels remain #130B07, never magenta.",
    3: "He lands on a rain-soaked rooftop, the same two fins snap shut, a ring of light flashes at his boots, the coat settles and he stands still. Keep the same face, costume, and visor. Cyan bounce #12B3B7 and magenta rim #E22D83 stay in narrow edge highlights; broad coat panels remain #130B07, never magenta.",
}


def request(shot):
    workflow = copy.deepcopy(json.loads(WORKFLOW.read_text()))
    workflow["3"]["inputs"]["text"] = LOCK + " " + ACTIONS[shot]
    workflow["4"]["inputs"]["text"] = NEGATIVE
    workflow["6"] = {
        "class_type": "LTXVImgToVideo",
        "inputs": {
            "positive": ["5", 0], "negative": ["5", 1], "vae": ["1", 2],
            "image": ["20", 0], "width": 1280, "height": 704,
            "length": 121, "batch_size": 1, "strength": 0.15,
        },
    }
    workflow["20"] = {"class_type": "LoadImage", "inputs": {"image": "drop-assassin-lock-shot3-2s.jpg"}}
    workflow["9"]["inputs"]["video_latent"] = ["6", 2]
    workflow["8"]["inputs"]["frames_number"] = 121
    workflow["10"]["inputs"]["noise_seed"] = 37000 + shot
    workflow["13"]["inputs"]["positive"] = ["6", 0]
    workflow["13"]["inputs"]["negative"] = ["6", 1]
    workflow["19"]["inputs"]["filename_prefix"] = f"video/drop-assassin-lock-shot-{shot}"
    return {"prompt": workflow, "client_id": "drop-assassin-lock"}


if __name__ == "__main__":
    if len(sys.argv) != 2 or not sys.argv[1].isdigit() or int(sys.argv[1]) not in ACTIONS:
        raise SystemExit("usage: render_locked_shots.py 1|2|3")
    print(json.dumps(request(int(sys.argv[1]))))
