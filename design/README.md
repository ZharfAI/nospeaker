# Design assets

Made with Codex image generation (the built-in `image_gen` tool), from one brief: three icon concepts, a wallpaper
for the screenshots and the README illustration. The current placeholder icon and a render of the app were attached
as references.

- `icon/icon-a.png` is the app icon. `app/build-app.sh` fits it to the macOS icon grid with
  `app/Support/make-icon.swift`; set `NOSPEAKER_ICON` to try `icon-b.png` or `icon-c.png` instead.
- `wallpaper/wallpaper.png` sits behind the window in `docs/images/hero.png` (`scripts/make-images.swift`).
- `../docs/images/what-it-does.png` is the README illustration.

The prompts Codex wrote for each image:

## Icon A — exact prompt

```text
Use case: logo-brand.
Asset: NoSpeaker macOS app icon concept A, one final icon, exactly 1024x1024 PNG.
Create a premium macOS Tahoe / Big Sur style app icon: a centered warm off-white paper rounded square squircle, about 80% of the canvas width and height, generous transparent padding. Subtle tactile depth, softly rounded bevel, soft top light, gentle drop shadow falling into genuine transparency.
Inside the squircle, a glossy ink-black glass trackpad seen straight on, a horizontal rounded rectangular slab. A single bold smooth sculptural silver-white sound waveform rises from the glass surface, clearly belonging to the trackpad, with a restrained reflection in the black glass. The waveform is the strong central mark, simple enough to read at 32 pixels. Trackpad and wave fill the body with balanced negative space, polished and distinctive, not a generic waveform inside an outline.
Palette: warm paper #F6F5F1, ink #0C0C0C, neutral graphite and silver greys only. Minimal composition, precise edges, rich material contrast, restrained terminal/ASCII heritage expressed through graphic clarity, not characters.
No text, letters, numbers, Apple logo, trademarks, color accents, photographic device imagery, clutter or thin hairlines. Outside the icon shape is actual alpha transparency, never a painted checkerboard or solid backdrop.
```

## Icon B — exact prompt

```text
Use case: logo-brand.
Asset: NoSpeaker macOS app icon concept B, single final icon, exactly 1024x1024 PNG.
Create a premium macOS Tahoe / Big Sur style app icon with a deep graphite rounded-square squircle body centered and filling approximately 80% of the canvas. Soft top lighting, restrained bevel and depth, gentle drop shadow. True transparent background outside the squircle.
Main subject: a brushed-aluminium external trackpad slab with a silver-grey glass surface, floating just above the graphite body in gentle three-quarter perspective. The slab is broad, thin, unmistakably a flat trackpad, not a speaker, screen or keyboard. Three bold concentric haptic ripple rings spread from one small fingertip-sized contact point on the glass; show only the point, no hand or person. As the ripples reach the far edge, their arcs lift off the glass into two clear sculptural sound-wave arcs. Make the transition visually coherent and simple, with a strong readable silhouette at 32 pixels.
Style: premium minimal app-icon render, refined metallic edges and restrained reflections, balanced negative space, crisp confident forms. Distinct from a frontal waveform mark.
Monochrome only: ink #0C0C0C, deep graphite, neutral brushed silver and warm off-white #F6F5F1 highlights. No color cast.
Avoid all text, letters, numbers, logos, Apple logo, trademarks, real product photos, people, clutter, tiny mechanical detail and hairline rings. Actual alpha transparency outside the icon, never a painted checkerboard or solid backdrop.
```

## Icon C — exact prompt

```text
Use case: logo-brand.
Asset: NoSpeaker macOS app icon concept C, one final icon, exactly 1024x1024 PNG.
A premium, minimal macOS Tahoe / Big Sur icon: warm off-white #F6F5F1 rounded-square squircle body, centered, about 80% of the canvas, true alpha transparency beyond its edges. Very subtle paper-ceramic depth, soft top light, a gentle drop shadow.
The central mark is bold ink-black #0C0C0C with exceptionally clear graphic geometry. In the upper half, one classic side-facing loudspeaker glyph, crossed out by one clean thick diagonal slash. Below it, a small horizontal trackpad shape, a filled shallow rounded rectangle with a slight silver top edge. From this lower trackpad, three bold rounded sound-wave arcs pour upward and outward along the right side. Clear visual hierarchy: speaker muted above, trackpad still sounding below. Keep speaker slash and trackpad sound waves spatially separate so the meaning reads immediately at 32 pixels. Balanced central composition, generous negative space.
Style: refined ink-on-paper symbol, mostly flat graphic with restrained embossed depth, confident thick strokes, optical balance, terminal/ASCII heritage without any characters. Clearly distinct from a realistic glass trackpad or ripple render.
Monochrome only: paper, ink, graphite and silver greys. No text, letters, numbers, logos, Apple logo, trademarks, real product photography, colored accents, people, clutter, thin hairlines, extra badges or border ornaments. Transparent outside the icon, never a checkerboard painted into the image.
```

## Wallpaper — exact prompt

```text
Use case: stylized-concept.
Asset: text-free desktop wallpaper for NoSpeaker screenshots, landscape 16:10, as large as supported, target 3840x2400 pixels.
Create a premium modern macOS-quality abstract wallpaper. Deep graphite to near-black space with a few broad, soft silver-white light ribbons flowing across it like slow sound waves. Elegant continuous wave geometry, layered translucent folds, sculpted diffuse light and controlled fine highlights; calm, spacious and restrained. Let the ribbons sweep across the lower and outer portions with a quieter dark middle region, so an off-white app window will stand out over it. Edge-to-edge full-bleed image, no framing.
Strictly monochrome: near-black #0C0C0C, graphite, neutral silver-white, no blue tint and no color accents. Perfectly smooth high-quality gradients and clean surfaces, refined contrast, no noisy texture, grain, banding or sharp distracting glow.
No text, letters, numbers, logos, watermarks, devices, people, music-note symbols, stars or decorative particles. Abstract flowing light only. Opaque background.
```

## README illustration — exact prompt

```text
Use case: stylized-concept.
Asset: text-free README explainer illustration for NoSpeaker, landscape 16:9, target 2048x1152 or largest supported at that aspect.
Create an elegant editorial technical print in ink #0C0C0C on warm off-white paper #F6F5F1, with neutral grey shading only. Bold confident lines, refined limited crosshatching, generous clear whitespace, a simple coherent three-quarter perspective, clean desk represented by a restrained horizontal plane.
Scene: a minimal open laptop with a blank screen, unlettered keys and no logos sits on the desk. Beside it is a separate thin flat external glass trackpad. Above the laptop's visible speaker grille floats one simple speaker glyph with a clear diagonal strike-through: the laptop speakers are muted. This muted symbol belongs unmistakably to the laptop.
From the separate trackpad's glass surface rise three clear bold sound-wave arcs and just three simple musical notes, showing that this glass itself makes music. In the trackpad's near-facing corner, a small integrated technical cutaway reveals one compact rectangular linear haptic actuator directly beneath the glass. Show a little suspended internal mass and short paired vibration motion marks around this motor. The actuator must look like a haptic motor, not a loudspeaker cone. The cutaway is part of this same trackpad, not a separate floating device.
Compose the laptop and trackpad as the only two devices, with the external sounding trackpad prominent and enough space that its cutaway, waves and notes remain legible. Minimal technically plausible hardware silhouettes; editorial illustration rather than a photograph or 3D glossy render. Match a monochrome terminal-heritage brand through spare, precise graphic design without ASCII characters.
No words, text, letters, numbers, labels, logos, Apple logo, trademarks, watermarks, people, hands, colored accents or extra desk accessories. The only floating marks are the muted-speaker symbol, sound-wave arcs, music notes and motor motion lines. Opaque warm off-white background.
```
