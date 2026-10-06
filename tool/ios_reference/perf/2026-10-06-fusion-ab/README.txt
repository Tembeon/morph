Menu frames with and without the fusion worker (menu_frames_test via audit.sh / audit_android.sh, 5 runs a launch; off = --dart-define=FUSION_PREFETCH=false of the same tree). fusion_ab.py output; the raw reports (5 - 7 MB each) are not committed. Labels: iphone-fusion3-off = baseline, iphone-fusion7-on = final; pixel6a-fusion4-off = baseline, pixel6a-fusion7-on = final; the intermediate on-runs are the steps glass-renderer.md lists as not helping (fusion/fusion3: one prediction or an adaptive horizon; fusion4/5: 2 / 3 predictions on the plain line; fusion2/5/6: iPhone one-ahead / three-ahead).

2026-10-06-iphone-fusion-diag      liquid   build 1.31 2.26 6.0 | raster 1.64 2.60 | over 0 | ahead 256 here 286
2026-10-06-iphone-fusion-diag2     liquid   build 1.37 2.34 6.1 | raster 1.68 2.82 | over 0 | ahead 278 here 264
2026-10-06-iphone-fusion-off-a     flat     build 0.75 2.42 4.8 | raster 0.66 1.44 | over 0 | ahead 0 here 1199
2026-10-06-iphone-fusion-off-a     liquid   build 1.34 2.65 5.9 | raster 1.57 2.51 | over 0 | ahead 0 here 1196
2026-10-06-iphone-fusion-off-b     flat     build 0.76 2.38 4.7 | raster 0.65 1.37 | over 0 | ahead 0 here 1198
2026-10-06-iphone-fusion-off-b     liquid   build 1.34 2.58 5.9 | raster 1.56 2.41 | over 0 | ahead 0 here 1195
2026-10-06-iphone-fusion-on-a      flat     build 0.74 1.71 4.7 | raster 0.69 1.47 | over 0 | ahead 612 here 586
2026-10-06-iphone-fusion-on-a      liquid   build 1.30 2.30 5.8 | raster 1.61 2.52 | over 0 | ahead 529 here 667
2026-10-06-iphone-fusion-on-b      flat     build 0.74 1.62 4.5 | raster 0.72 1.47 | over 0 | ahead 662 here 535
2026-10-06-iphone-fusion-on-b      liquid   build 1.33 2.27 5.7 | raster 1.63 2.54 | over 0 | ahead 530 here 666
2026-10-06-iphone-fusion2-off-a    flat     build 0.74 2.46 4.9 | raster 0.68 1.59 | over 0 | ahead 0 here 1196
2026-10-06-iphone-fusion2-off-a    liquid   build 1.42 2.66 5.9 | raster 1.59 2.52 | over 0 | ahead 0 here 1196
2026-10-06-iphone-fusion2-off-b    flat     build 0.75 2.41 4.6 | raster 0.67 1.48 | over 0 | ahead 0 here 1197
2026-10-06-iphone-fusion2-off-b    liquid   build 1.36 2.57 5.7 | raster 1.56 2.48 | over 0 | ahead 0 here 1196
2026-10-06-iphone-fusion2-on-a     flat     build 0.74 1.55 4.6 | raster 0.69 1.42 | over 0 | ahead 713 here 485
2026-10-06-iphone-fusion2-on-a     liquid   build 1.30 2.27 5.8 | raster 1.63 2.47 | over 0 | ahead 610 here 583
2026-10-06-iphone-fusion2-on-b     flat     build 0.75 1.59 4.9 | raster 0.70 1.43 | over 0 | ahead 741 here 456
2026-10-06-iphone-fusion2-on-b     liquid   build 1.28 2.30 5.8 | raster 1.63 2.50 | over 0 | ahead 592 here 602
2026-10-06-iphone-fusion3-off-a    flat     build 0.74 2.45 4.6 | raster 0.64 1.45 | over 0 | ahead 0 here 1199
2026-10-06-iphone-fusion3-off-a    liquid   build 1.34 2.67 5.5 | raster 1.56 2.47 | over 0 | ahead 0 here 1196
2026-10-06-iphone-fusion3-off-b    flat     build 0.74 2.42 4.6 | raster 0.65 1.39 | over 0 | ahead 0 here 1197
2026-10-06-iphone-fusion3-off-b    liquid   build 1.36 2.67 5.9 | raster 1.58 2.52 | over 0 | ahead 0 here 1194
2026-10-06-iphone-fusion3-on-a     flat     build 0.75 1.58 4.6 | raster 0.68 1.47 | over 0 | ahead 720 here 478
2026-10-06-iphone-fusion3-on-a     liquid   build 1.32 2.25 5.8 | raster 1.56 2.48 | over 0 | ahead 612 here 582
2026-10-06-iphone-fusion3-on-b     flat     build 0.82 1.57 4.0 | raster 0.77 1.56 | over 0 | ahead 621 here 577
2026-10-06-iphone-fusion3-on-b     liquid   build 1.30 2.40 5.5 | raster 1.56 2.61 | over 0 | ahead 590 here 604
2026-10-06-iphone-fusion5-on-a     flat     build 0.76 1.62 4.8 | raster 0.72 1.52 | over 0 | ahead 795 here 403
2026-10-06-iphone-fusion5-on-a     liquid   build 1.29 2.26 5.8 | raster 1.60 2.58 | over 0 | ahead 691 here 508
2026-10-06-iphone-fusion5-on-b     flat     build 0.76 1.60 4.7 | raster 0.73 1.65 | over 0 | ahead 711 here 487
2026-10-06-iphone-fusion5-on-b     liquid   build 1.31 2.39 6.0 | raster 1.65 2.59 | over 0 | ahead 687 here 507
2026-10-06-iphone-fusion6-on       flat     build 0.74 1.64 4.8 | raster 0.71 1.54 | over 0 | ahead 787 here 412
2026-10-06-iphone-fusion6-on       liquid   build 1.29 2.32 5.6 | raster 1.60 2.59 | over 0 | ahead 683 here 510
2026-10-06-iphone-fusion7-on-a     flat     build 0.76 1.57 4.7 | raster 0.71 1.56 | over 0 | ahead 772 here 427
2026-10-06-iphone-fusion7-on-a     liquid   build 1.34 2.32 6.1 | raster 1.59 2.60 | over 0 | ahead 670 here 528
2026-10-06-iphone-fusion7-on-b     flat     build 0.76 1.52 4.7 | raster 0.72 1.53 | over 0 | ahead 792 here 406
2026-10-06-iphone-fusion7-on-b     liquid   build 1.31 2.28 5.9 | raster 1.59 2.54 | over 0 | ahead 723 here 473
2026-10-06-pixel6a-fusion-off-a    flat-off build 2.52 11.53 35.5 | raster 5.30 12.76 | over 4 | ahead 0 here 573
2026-10-06-pixel6a-fusion-off-a    liquid-off build 5.88 13.62 26.4 | raster 8.90 14.59 | over 12 | ahead 0 here 544
2026-10-06-pixel6a-fusion-off-b    flat-off build 2.80 12.53 21.4 | raster 4.93 10.35 | over 7 | ahead 0 here 560
2026-10-06-pixel6a-fusion-off-b    liquid-off build 5.84 15.26 33.1 | raster 9.56 16.56 | over 17 | ahead 0 here 520
2026-10-06-pixel6a-fusion-on-a     flat-on  build 2.36 11.07 24.5 | raster 4.76 9.98 | over 5 | ahead 254 here 308
2026-10-06-pixel6a-fusion-on-a     liquid-on build 5.42 13.87 25.6 | raster 9.26 14.95 | over 8 | ahead 241 here 301
2026-10-06-pixel6a-fusion-on-b     flat-on  build 2.36 12.41 21.6 | raster 4.92 10.24 | over 7 | ahead 202 here 352
2026-10-06-pixel6a-fusion-on-b     liquid-on build 5.75 14.41 34.5 | raster 9.65 15.71 | over 13 | ahead 215 here 317
2026-10-06-pixel6a-fusion3-off-a   flat-off build 2.65 12.57 29.4 | raster 5.21 10.88 | over 8 | ahead 0 here 555
2026-10-06-pixel6a-fusion3-off-a   liquid-off build 5.75 13.49 33.7 | raster 9.20 15.61 | over 12 | ahead 0 here 541
2026-10-06-pixel6a-fusion3-off-b   flat-off build 2.69 12.36 27.5 | raster 5.16 10.64 | over 5 | ahead 0 here 562
2026-10-06-pixel6a-fusion3-off-b   liquid-off build 6.05 16.06 32.1 | raster 8.89 15.92 | over 17 | ahead 0 here 512
2026-10-06-pixel6a-fusion3-on-a    flat-on  build 2.35 10.43 27.3 | raster 5.07 9.96 | over 5 | ahead 275 here 297
2026-10-06-pixel6a-fusion3-on-a    liquid-on build 5.63 14.80 38.8 | raster 9.28 15.78 | over 13 | ahead 232 here 302
2026-10-06-pixel6a-fusion3-on-b    flat-on  build 2.49 11.82 42.6 | raster 4.78 10.05 | over 7 | ahead 254 here 306
2026-10-06-pixel6a-fusion3-on-b    liquid-on build 5.57 14.56 33.9 | raster 9.38 15.92 | over 15 | ahead 255 here 276
2026-10-06-pixel6a-fusion4-off-a   flat-off build 2.51 12.03 26.9 | raster 5.07 11.08 | over 8 | ahead 0 here 559
2026-10-06-pixel6a-fusion4-off-a   liquid-off build 5.50 13.97 32.5 | raster 9.13 15.28 | over 16 | ahead 0 here 531
2026-10-06-pixel6a-fusion4-off-b   flat-off build 2.67 12.37 23.8 | raster 5.20 11.46 | over 6 | ahead 0 here 561
2026-10-06-pixel6a-fusion4-off-b   liquid-off build 6.04 15.06 36.2 | raster 9.26 15.59 | over 13 | ahead 0 here 519
2026-10-06-pixel6a-fusion4-on-a    flat-on  build 2.46 9.85 25.9 | raster 4.78 9.30 | over 3 | ahead 309 here 260
2026-10-06-pixel6a-fusion4-on-a    liquid-on build 5.24 11.68 31.0 | raster 8.90 14.77 | over 9 | ahead 330 here 225
2026-10-06-pixel6a-fusion4-on-b    flat-on  build 2.42 11.12 28.7 | raster 5.04 10.55 | over 6 | ahead 298 here 260
2026-10-06-pixel6a-fusion4-on-b    liquid-on build 5.62 15.51 34.6 | raster 8.58 15.56 | over 13 | ahead 229 here 300
2026-10-06-pixel6a-fusion5-on-a    flat-on  build 2.55 11.41 29.2 | raster 5.01 9.32 | over 6 | ahead 248 here 320
2026-10-06-pixel6a-fusion5-on-a    liquid-on build 5.87 15.22 35.0 | raster 8.73 15.78 | over 15 | ahead 240 here 288
2026-10-06-pixel6a-fusion5-on-b    flat-on  build 2.58 11.85 24.5 | raster 5.73 10.93 | over 6 | ahead 214 here 351
2026-10-06-pixel6a-fusion5-on-b    liquid-on build 5.71 13.19 31.0 | raster 8.50 15.17 | over 10 | ahead 247 here 287
2026-10-06-pixel6a-fusion7-on-a    flat-on  build 2.61 11.22 22.6 | raster 5.22 9.92 | over 4 | ahead 319 here 246
2026-10-06-pixel6a-fusion7-on-a    liquid-on build 5.75 13.25 35.5 | raster 9.05 14.95 | over 14 | ahead 372 here 166
2026-10-06-pixel6a-fusion7-on-b    flat-on  build 2.46 10.90 28.8 | raster 5.28 9.63 | over 5 | ahead 316 here 254
2026-10-06-pixel6a-fusion7-on-b    liquid-on build 5.97 13.62 27.5 | raster 8.73 15.58 | over 10 | ahead 353 here 186

Served pairs re-fused on the host (outline distance served vs the frame's own fusion):
== pixel6a-fusion7-on-a/liquid-on
inputs within 0.02: n 372 outline distance p50 0.0181 p95 0.0225 max 0.0275 pt
== pixel6a-fusion7-on-a/flat-on
inputs within 0.02: n 319 outline distance p50 0.0182 p95 0.0237 max 0.0544 pt
== iphone-fusion7-on-a/liquid
inputs within 0.02: n 670 outline distance p50 0.0182 p95 0.0239 max 0.0602 pt
== iphone-fusion7-on-a/flat
inputs within 0.02: n 772 outline distance p50 0.0180 p95 0.0229 max 0.0314 pt
