# Drop Assassin — character lock

**Lock name:** Slit.

One face. One costume. One grade. Every later frame uses this page. The character paragraph below is copied as a block. Action is appended after it.

Hero plate: [refs/lock-shot3-2s.jpg](refs/lock-shot3-2s.jpg), shot 3 at 2.0 s. Face and fin: [refs/lock-face.jpg](refs/lock-face.jpg), [refs/lock-fin.jpg](refs/lock-fin.jpg).

## The call

Shot 3 is the character. Hood up, one crimson visor band, matte-black longcoat, silver sleeve filaments, two folded carbon fins.

Shot 2 keeps the teal-and-magenta grade, and nothing else. Its full mask and chest glider stay an alternate, filed below.

Shot 1 is retired. Bare face, white chest emblem, six-blade wing rig.

## Face

- Hood up, always. The hood is matte black and shadows the brow.
- One solid horizontal visor across the eyes. Opaque crimson. No pupils, no blink, no split into two eye holes.
- Lower face only: fair skin, small nose, closed mouth, smooth jaw, no beard, no teeth, ears hidden in the hood.
- Jaw skin on the 2.0 s plate averages **#D6814F**. The visor band on that same plate averages **#BF312F**, with a hot core at **#F4373B**.
- Same person in every shot. The visor is the identity. The jaw is a fixed sliver under it.

## Costume

- Matte-black double-breasted longcoat to the ankles. High collar, two dark buttons, hood. Coat body on the 2.0 s plate averages **#130B07**. It stays that black when the rim light hits.
- Thin silver filament along each shoulder seam and down the outer sleeve. A highlight on that line reads **#C4C7C8**. The line stays a cord, not a wide stripe.
- Black gloves. Black combat boots. No chest badge, no belt gadgets, no glowing buckle.
- Drop rig: two carbon fins on the upper back, folded at rest. Carbon weave, silver leading edge. The fin on the figure’s right (viewer left) sits a little more open than its pair. They are the same design.
- In flight those same two fins open. They stay two blades with silver edges. This open state is not in the shot 3 plate. It is specified so a later pass does not borrow another wing.

## Grade

High contrast. Crushed blacks. Wet highlights. Teal fill, magenta only as a rim.

| Role | Hex | Measured from |
| --- | --- | --- |
| Coat | `#130B07` | Shot 3, 2.0 s, torso average |
| Visor | `#BF312F` | Shot 3, 2.0 s, visor-band average |
| Visor core | `#F4373B` | Shot 3, 2.0 s, hottest visor pixel |
| Jaw | `#D6814F` | Shot 3, 2.0 s, skin under the visor |
| Silver filament | `#C4C7C8` | Shot 3, 2.0 s, piping highlight |
| Night teal | `#091E27` | Shot 3, 2.0 s, right-sky average |
| Sky magenta haze | `#943C62` | Shot 3, 0.0 s, top-left corner |
| Cyan bounce | `#12B3B7` | Shot 2, 2.5 s, neon peak |
| Magenta rim | `#E22D83` | Shot 2, 2.5 s, neon peak |

Shot 3 is teal-heavy. The magenta on that plate is a corner haze. The rim and the cyan bounce are taken from shot 2 so the grade matches the brief: teal and magenta, together. The coat does not turn red. Magenta lives on the hood edge, the coat rim, and the fin tips.

These hex values are averages and peaks from JPEG frames pulled out of the h264 files. They are a match target, not a calibrated LUT.

Frame: **1280×704**, **24 fps**, to match the three plates. No on-screen text.

## Canonical prompt

Paste this block unchanged. Add the action sentence after it.

```
Drop Assassin, the same hooded figure in every shot. Matte-black double-breasted tactical longcoat to the ankles, hood up, high collar. One solid horizontal crimson visor band across the eyes, opaque, no visible eyes. Fair lower face, small nose, closed mouth, no beard, jaw in shadow. Thin silver filament seams along the shoulder seams and outer sleeves. Black gloves, black combat boots. A compact carbon drop-rig of two folded fins on the upper back, carbon weave, silver leading edges. High-contrast cinematic grade, crushed blacks, teal night fill, hard magenta rim light on the hood edge and coat rim only, the coat stays matte black, wet highlights. No on-screen text, HD.
```

Negative, carried from the original plates, plus the identity rejects:

```
blurry, low quality, distorted, deformed, watermark, text artifacts, pc game, video game, cartoon, ugly, bare face, visible eyes, two eye slits, full face mask, white chest emblem, six wings, spider wings, chest glider, red suit, beard, smile, teeth, different person
```

Action lines, if a new pass needs them:

- Fall: free-fall headfirst, coat snapping, the same two fins beginning to open.
- Canyon: the same figure between glass towers, fins open as those two blades, one gloved hand cutting the rain.
- Roof: lands on a rain-soaked rooftop, fins snap shut, a ring of light at the boots, coat settles, still stance.

## Motion

- Rest, as in shot 3 from 2 s to 4 s: feet apart, arms at the sides, coat hanging, fins folded, visor steady.
- Landing, as in the opening of shot 3: low view, impact light at the boots, coat catches up a beat later.
- The visor does not blink and does not break into two lights.
- A magenta flash may rim the silhouette. It does not recolor the coat. Shot 1 at about 3 s floods the suit crimson. That pass is the mistake.

## Type and voice

No type inside the picture.

If a slate is cut in front of the shot: **DROP ASSASSIN**, condensed sans, all caps, wide tracking, `#C4C7C8` on `#130B07`.

He barely speaks. Cold, short, no jokes.

> The city blinks first.

## Alternate

**Mask.** Shot 2 at 2.5 s, [refs/alt-shot2-2p5s.jpg](refs/alt-shot2-2p5s.jpg). Full matte-black mask, two crimson eye slits, hood, chest harness, wide carbon glider. Use this only if the jaw on Slit keeps changing person between frames. The longcoat and the two fins still win. The mask would replace the visor and the jaw, and the glider would not come with it.

## Retired

Shot 1 at 2.0 s, [refs/reject-shot1-2s.jpg](refs/reject-shot1-2s.jpg). Open face, fitted suit, white piping, silver chest plate, a fan of long blades. Do not feed this plate back in as a reference.

## Sources checked this session

Downloaded from Drive folder `1rCKsZjcBPv2pPoYBbo2wVI3xnwJfQ3j5` and opened locally:

| File | Drive id | Checked |
| --- | --- | --- |
| `shot-1.mp4` | `1xk5pclbB8Nm1r6-A3oH0yYr-uioZUwij` | 1,265,363 bytes, h264, 1280×704, 24 fps, 5.04 s. Frames at 0, 1, 2, 3, 4 s. |
| `shot-2.mp4` | `1wzyNOIBMdMsbI1brPUpAe7FCtR4vwVjR` | 1,882,150 bytes, same size and length. Frames at 0.5, 1.5, 2.5, 3.5, 4.5 s. |
| `shot-3.mp4` | `1lOm-aQ5QpvEJY77q0sXo2gF-09sXYmHY` | 1,398,470 bytes, same size and length. Frames at 0, 1, 2, 3, 4.17 s. |

Each file’s metadata names the checkpoint `ltx-2.3-22b-distilled-fp8.safetensors`. Matching that checkpoint on the next pass is a continuity note for Operations. This session did not run ComfyUI.

## Not verified

- No new frame was rendered from this lock.
- `final.mp4` in that Drive folder was not opened. The Mac path `~/Documents/Jarvis Workspace/Results/.../final.mp4` was not opened.
- Audio on the three files was not reviewed.
- Hex values were read from compressed frames, on an uncalibrated display path.
- The open-fin flight pose for this coat is specified here and was not seen on the shot 3 plate.
