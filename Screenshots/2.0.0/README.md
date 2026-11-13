# App Store screenshots, 2.0.0

`<lang>/` holds what is uploaded to App Store Connect: `1-iphone` … `5-iphone` (1206×2622) and `6-ipad13` (2048×2732).

They are rendered from simulator screenshots (iPhone 17 Pro Max, iPad Pro 13-inch, light mode, 9:41) with the captions in `captions-<lang>.json`:

    swift render.swift captions-en.json <simulator shots dir> en

The source shots are named after the first field of each slide: `1-search`, `2-forms`, `3-learn`, `4-exercise`, `5-table`, `ipad`.
