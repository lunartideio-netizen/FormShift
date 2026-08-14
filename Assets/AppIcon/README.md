# FormShift App Icon

The production icon uses two interlocking conversion tracks that form an
abstract `S`: Cobalt moves toward the destination, Graphite returns toward the
source, and the Process Amber node marks the handoff. The ceramic shell matches
the app's interface palette.

The initial direction was explored with OpenAI's built-in image generation
tool using this final concept prompt:

> A native macOS icon for FormShift, built from two interlocking directional
> conversion rails forming an abstract S. Use Ceramic #F7F8FA, Machine Silver
> #E7E9ED, Graphite #20242A, Cobalt #3267E3, and one Process Amber #E99A2E
> status node. Keep a bold centered silhouette, restrained satin material,
> transparent outer corners, no text, no document, cloud, upload, or recycle
> symbols, and strong legibility at 16px.

Generated concept images were not shipped because their transparent edges were
not clean enough. `Scripts/generate-app-icon.swift` implements the selected
direction as deterministic vector-like Core Graphics artwork.

Regenerate the PNG master and all `.icns` sizes with:

```sh
Scripts/build-app-icon.sh
```
