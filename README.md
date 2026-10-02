# filmkit

Photo and video editing for Flutter: crop, trim, LUT filters and adjustments, exported natively (Media3 Transformer on Android, AVFoundation on iOS), with an Instagram-style editor screen.

> **Status**: early development, nothing usable yet.

## Principles

- The editing UI is Flutter; everything that produces a file is native.
- Filters are 3D LUTs, shared by the live preview (Flutter shader) and the native export, so that the preview and the exported file look the same.
- Edits are described by a serializable `EditSpec`, exportable with or without the editor screen.
- Picker-agnostic input: a file path or a photo_manager `AssetEntity` (e.g. from insta_assets_picker).
