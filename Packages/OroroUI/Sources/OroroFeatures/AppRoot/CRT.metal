#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// A CRT tube drawn over the loading screen (`CRTFrame` holds the per-frame values; `PowerOnCurve` animates them):
// curved glass, the lit raster squeezing the picture as deflection builds up, overexposure and white wash, a halo
// around the hot beam, soft focus, red/blue misconvergence, deflection wobble, scanlines, static, a rolling hum bar,
// vignette and a faint glass reflection.

namespace {
    constant half3 offGlass = half3(0.024, 0.012, 0.012);   // #060303, the unlit tube (and the launch screen)
    constant half3 hotBeam = half3(1.0, 0.95, 0.86);        // white-hot phosphor

    // How strongly the tube shows at full strength.
    constant float curvature = 0.10;      // barrel bulge of the glass
    constant float scanDepth = 0.4;       // darkening at a scanline's centre
    constant float vignetteDepth = 0.55;  // darkening towards the curved edges
    constant float reflection = 0.035;    // the glass's faint highlight
    constant float scanSpeed = 14.0;      // points per second the scanlines roll down

    float hash(float2 p) {
        return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
    }

    /// 0…1 darkening of a scanline at `y` points down the glass: soft-edged lines rolling slowly downwards, their
    /// depth trembling a little like a real raster.
    float scanShade(float y, float time, float period) {
        float phase = fract((y - time * scanSpeed) / period);
        float band = 0.5 - 0.5 * cos(phase * 2.0 * M_PI_F);
        return band * (0.9 + 0.1 * sin(time * 53.0 + y * 0.02));
    }

    half4 focus(SwiftUI::Layer layer, float2 p, float blur) {
        if (blur < 0.05) return layer.sample(p);
        half4 sum = layer.sample(p) * 2.0h;
        sum += layer.sample(p + float2(blur, 0)) + layer.sample(p - float2(blur, 0));
        sum += layer.sample(p + float2(0, blur)) + layer.sample(p - float2(0, blur));
        return sum / 6.0h;
    }
}

[[ stitchable ]] half4 crt(float2 position, SwiftUI::Layer layer, float2 size, float time,
                          float rasterWidth, float rasterHeight, float exposure, float wash,
                          float blur, float split, float wobble, float noise, float scanPeriod, float strength) {
    // `strength` fades the whole tube (glass, scanlines, vignette, reflection, static, fringing) out: 0 is the
    // flat modern picture, untouched.
    if (strength <= 0.0) return layer.sample(position);

    // Curved glass: points near the edges map further out, so the picture bulges and the corners round off.
    float2 centred = position / size - 0.5;
    float2 glass = centred * (1.0 + curvature * strength * dot(centred, centred) * 4.0);
    if (any(abs(glass) > 0.5)) return half4(0, 0, 0, 1);

    // The lit raster, in points from the centre; soft at the beam's ends, crisp along its edges.
    float2 fromCentre = abs(glass) * size;
    float2 halfRaster = float2(rasterWidth, rasterHeight) * size * 0.5;
    float lit = (1.0 - smoothstep(halfRaster.x - 0.02 * size.x * (1.0 - rasterHeight), halfRaster.x + 1.0, fromCentre.x))
              * (1.0 - smoothstep(halfRaster.y, halfRaster.y + 1.5, fromCentre.y));

    // The picture squeezed into the raster, nudged by the deflection wobble.
    float2 squeezed = 0.5 + glass / max(float2(rasterWidth, rasterHeight), 1e-4);
    float2 source = clamp(squeezed * size + float2(wobble * sin(squeezed.y * 9.0 + time * 40.0), 0), 0.0, size);

    // Misconvergence: red and blue land a little apart from green.
    float fringe = split * strength;
    half3 colour = half3(focus(layer, source + float2(fringe, 0), blur).r,
                         focus(layer, source, blur).g,
                         focus(layer, source - float2(fringe, 0), blur).b);
    colour = colour * exposure + hotBeam * wash * exposure * 0.25h;
    colour = mix(offGlass, colour, half(lit));

    // Halo: light from the hot beam bleeding into the glass around it.
    float2 outside = max(fromCentre - halfRaster, 0.0);
    // Strongest while the beam is a hot line (wash and exposure high), fading as the picture opens.
    float halo = wash * exposure * 0.12 * exp(-outside.y / 36.0) * exp(-outside.x / 80.0);
    colour += hotBeam * halo;

    // Scanlines, static, and the hum bar rolling slowly down the picture.
    float scan = 1.0 - scanDepth * strength * scanShade((glass.y + 0.5) * size.y, time, scanPeriod);
    colour *= half(mix(1.0, scan, lit));
    colour += half((hash(floor(position) + fract(time) * 97.0) - 0.5) * noise * strength * lit);
    float bar = fract(time * 0.11);
    colour *= half(1.0 - 0.05 * strength * lit * smoothstep(0.08, 0.0, abs(glass.y + 0.5 - bar)));

    // Vignette towards the curved edges, and a faint reflection on the glass.
    float edge = length(glass * float2(1.0, size.y / size.x) * 2.0);
    colour *= half(1.0 - vignetteDepth * strength * smoothstep(0.5, 1.15, edge));
    colour += half(reflection * strength * smoothstep(0.35, 0.0, length(glass - float2(-0.22, -0.28))));

    return half4(clamp(colour, 0.0h, 1.0h), 1.0h);
}

// The same tube drawn over a live screen that can't be sampled (UIKit-backed views can't go through a layer
// effect): a premultiplied colour composited source-over, so its alpha darkens what is beneath (the curved glass's
// edges, scanlines, vignette, hum bar) and its rgb adds light (grain, the glass reflection).
// `strength` fades the whole tube out; 0 draws nothing.
[[ stitchable ]] half4 crtOverlay(float2 position, half4 color, float2 size, float time,
                                 float strength, float noise, float scanPeriod) {
    float2 centred = position / size - 0.5;
    float2 glass = centred * (1.0 + curvature * strength * dot(centred, centred) * 4.0);
    if (any(abs(glass) > 0.5)) return half4(0, 0, 0, half(strength));

    float scan = scanDepth * strength * scanShade((glass.y + 0.5) * size.y, time, scanPeriod);
    float edge = length(glass * float2(1.0, size.y / size.x) * 2.0);
    float vignette = vignetteDepth * strength * smoothstep(0.5, 1.15, edge);
    float bar = 0.05 * strength * smoothstep(0.08, 0.0, abs(glass.y + 0.5 - fract(time * 0.11)));
    float grain = (hash(floor(position) + fract(time) * 97.0) - 0.5) * noise;
    float dark = 1.0 - (1.0 - scan) * (1.0 - vignette) * (1.0 - bar) * (1.0 - max(-grain, 0.0));
    float light = max(grain, 0.0) + reflection * strength * smoothstep(0.35, 0.0, length(glass - float2(-0.22, -0.28)));
    return half4(half3(light), half(dark));
}
