End frame per run: 574 (base), 574 (timedretry); each window starts at the run's own end frame and is cut to the frames every run has, slack 0, 3 runs per arm; a window with fewer frames than its minimum in any run is noData.

| window | timedretry |
|---|---|
| approach | noGain [34 frames, min 34] |
| end 0-19 | noGain; less: LayoutCount 21 to 7, Paint 335 to 177, RasterTask 517 to 124, PaintImage 495 to 185, FireAnimationFrame 43 to 23; more: RecalcStyleCount 43 to 51 [20 frames, min 20] |
| end 20-59 | noGain; less: LayoutCount 25 to 0, Paint 252 to 192, RasterTask 454 to 0, PaintImage 454 to 188, FireAnimationFrame 141 to 119; more: RecalcStyleCount 40 to 42 [40 frames, min 40] |
| end 60-119 | noGain; more: Paint 120 to 151, PaintImage 240 to 271 [60 frames, min 60] |
| end 120+ | noGain [47 frames, min 20] |
| finish | noGain; less: LayoutCount 52 to 13, Paint 915 to 729, RasterTask 1207 to 360, PaintImage 1514 to 970, FireAnimationFrame 400 to 358; more: RecalcStyleCount 320 to 329 [201 frames, min 174] |
