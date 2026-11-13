# THE EXACT ONE

A concept film for Drop Assassin. Revision 3, 2026-11-13. **Unapproved draft.** Research has not reviewed it, and nobody has signed it off.

Opening card plus eight scenes, a planned 6:58 at 24 fps, with no narrator. Alex Rivera misses a drop, catches the restock with Drop Assassin, logs his shelf, and hunts down the one chase he doesn't own.

## Files

| File | What it is |
| --- | --- |
| [`the-exact-one.pdf`](the-exact-one.pdf) | The script in standard screenplay format, 8 pages. Start here. |
| [`the-exact-one.fountain`](the-exact-one.fountain) | The same script as [Fountain](https://fountain.io) plain text, for Highland, Beat, Slugline or any Fountain editor. |
| [`screenplay.md`](screenplay.md) | The full production text: direction, palette, status labels, picture rules, character and prop bible, scenes and copy deck. |
| [`source/revision-3-drive-export.md`](source/revision-3-drive-export.md) | The Drive file exactly as saved, including the run header and Revision 3 change notes. |

The source is the Drive file [2026-11-13 Story consultation Creative Director f9164a7b.md](https://drive.google.com/file/d/1lIwBBMKfuQhy6v8jS_s9tazWTt2bXhPN/view?usp=drivesdk) from Cursor run [bc-f1af9864](https://cursor.com/agents/bc-f1af9864-1b21-4f2b-b08c-5c5fb5c7f71c). The script's words are unchanged. Only the formatting is new.

## Rebuild and check

```bash
python3 scripts/screenplay.py build   # screenplay.md and the .fountain file, from the source
python3 scripts/screenplay.py pdf     # the PDF; needs: pip install 'screenplain[PDF]'
python3 scripts/screenplay.py check   # needs nothing; add pymupdf to also check the PDF text
```

`check` confirms the following:

- The source still matches the saved Drive file's hash.
- `screenplay.md` is the revision 3 text, unedited.
- The scene timings run from 0:00 to 6:58 with no gaps, which matches the 418-second runtime.
- Every spoken line matches the copy deck word for word and in order.
- All 158 on-screen strings come from the copy deck, and none has a currency symbol.
- The Fountain file and the PDF carry every line.

## Open before anyone renders or sends this

1. **Research review of this text.** The 02:03 Research review never received the draft. It checked Iron Man and J.A.R.V.I.S. place names, which this script does not contain. Research should review the files above.
2. **Shipped screens.** Intel, Body Count, Hunt and Lock On appear without the "Upcoming preview" chip. Each one keeps that status only if Research confirms it has shipped.
3. **Palette.** The hex values are proposals. They have not been checked against the Drop Assassin brand doc, which is not in this repository.
4. **Brandon's calls.**
   - Keep the placeholder collectibles (Violet Lantern, Harbor Lantern, Redline Racer), or swap in verified ones.
   - Supply the logo file for the end card.
   - Decide whether the hooded assassin locked in `docs/drop-assassin/character-lock.md` (on its own branch) belongs in this film. The film currently does not use it.
5. **Approval.** The approval step is on hold: there is no distribution list, no review criteria and no timeline yet. Nothing has been sent.
