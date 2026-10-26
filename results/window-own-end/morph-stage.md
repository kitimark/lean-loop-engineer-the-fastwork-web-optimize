End frame per run: 574 (base), 670 (stage); each window starts at the run's own end frame and is cut to the frames every run has, slack 0, 3 runs per arm.

| window | stage |
|---|---|
| approach | noGain; less: RecalcStyleCount 129 to 95, FireAnimationFrame 120 to 77; more: LayoutCount 6 to 30, Paint 114 to 272, RasterTask 236 to 637, PaintImage 137 to 617 [34 frames] |
| end 0-19 | gain; less: RecalcStyleCount 12 to 5, LayoutCount 4 to 1, Paint 179 to 9, RasterTask 115 to 19, PaintImage 62 to 24, FireAnimationFrame 11 to 9 [3 frames] |
| end 20-59 | noData (not usable) [0 frames] |
| end 60-119 | noData (not usable) [0 frames] |
| end 120+ | noData (not usable) [0 frames] |
| finish | noGain; less: RecalcStyleCount 141 to 100, Paint 293 to 281, FireAnimationFrame 131 to 86; more: LayoutCount 10 to 31, RasterTask 351 to 656, PaintImage 199 to 641 [37 frames] |
