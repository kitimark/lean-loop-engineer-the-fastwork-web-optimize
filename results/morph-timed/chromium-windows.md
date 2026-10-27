End frame per run: 574 (base), 574 (timed); each window starts at the run's own end frame and is cut to the frames every run has, slack 0, 3 runs per arm; a window with fewer frames than its minimum in any run is noData.

| window | timed |
|---|---|
| approach | noGain [34 frames, min 34] |
| end 0-19 | noGain; less: Paint 243 to 177, RasterTask 319 to 124, FireAnimationFrame 43 to 23; more: RecalcStyleCount 48 to 51, LayoutCount 6 to 7, PaintImage 124 to 185 [20 frames, min 20] |
| end 20-59 | noGain; less: Paint 216 to 192, RasterTask 139 to 0, FireAnimationFrame 141 to 119; more: RecalcStyleCount 40 to 42, PaintImage 187 to 188 [40 frames, min 40] |
| end 60-119 | noGain [60 frames, min 60] |
| end 120+ | noGain [47 frames, min 20] |
| finish | noGain; less: Paint 819 to 729, RasterTask 694 to 360, FireAnimationFrame 400 to 358; more: RecalcStyleCount 325 to 329, LayoutCount 12 to 13, PaintImage 909 to 969 [201 frames, min 174] |
