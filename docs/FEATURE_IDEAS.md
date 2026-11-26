# Small, useful screenshot features to consider

2026-10-23. Keep the app local, free and focused. These are options, not commitments to add everything.

## Added in this iteration

- **WYSIWYG text:** fixed wrapping width at the screenshot edge, shared live/output layout, preserved explicit newlines, spaces and annotation color.
- **Plain line (L):** existing color/thickness controls, endpoint handles, selection, move, undo/redo and all export destinations.
- **Highlighter (H):** translucent yellow by default, with its own color selection. Drag a rectangular highlight over text; move and resize it with Selection. Text remains visible through the marker.
- **Small-capture sizing:** the editor now reserves room for the full markup toolbar, so tools stay visible instead of moving into the overflow menu.
- **Silent MP4 recording:** record a region to H.264 `.mp4` with no audio. Animated GIF and audio capture remain planned follow-ups.

The magnifier callout was tried and removed at the user's request.

## Best next candidates for this app

| Feature | Why consider it? | Relative effort |
|---|---|---|
| Solid redaction rectangle | Deliberately cover account numbers or names before exporting. | Small |
| Shift-constrained lines/arrows | Quickly draw horizontal, vertical or 45-degree strokes. | Small |
| Open/paste an existing image | Annotate images already saved or received without taking another capture. | Small–medium |
| OCR: Copy Text | Copy otherwise unselectable text from part of a screenshot. Keep recognition local. | Medium |
| Pin screenshot on top | Keep a reference visible while working in another app. | Small–medium |
| Delayed/window capture | Capture an open menu or one window without manual cropping. | Medium |
| Spotlight | Dim everything except a selected region; useful when a magnifier is unnecessary. | Small–medium |
| Combine two screenshots | Show a comparison or an annotated sequence in one image. | Medium |
| Scrolling capture | Capture long pages or conversations. Useful, but stitching and app-specific scrolling need substantially more testing. | Large |

Recommendation: solid redaction and constrained drawing next; then choose between OCR and pinning based on actual use. Recording is now limited to silent MP4 capture; keep cloud hosting, a full video editor (trimming, transitions) and a permanent screenshot library out of the immediate scope. Animated GIF and audio capture are the two remaining recording follow-ups.

## Reference products

[CleanShot's feature list](https://cleanshot.com/features) includes highlighting, lines, shapes, image combining, floating screenshots, OCR, capture history and scrolling capture. [Shottr](https://shottr.cc/) demonstrates OCR, pinning, image combining, pixelation, measurement tools and scrolling screenshots. Their feature lists are inspiration; neither their full scope nor their business model needs to become VibeShot's scope.
