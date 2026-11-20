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

    float hash(float2 p) {
        return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
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
                          float blur, float split, float wobble, float noise, float scanPeriod) {
    // Curved glass: points near the edges map further out, so the picture bulges and the corners round off.
    float2 centred = position / size - 0.5;
    float2 glass = centred * (1.0 + 0.07 * dot(centred, centred) * 4.0);
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
    half3 colour = half3(focus(layer, source + float2(split, 0), blur).r,
                         focus(layer, source, blur).g,
                         focus(layer, source - float2(split, 0), blur).b);
    colour = colour * exposure + hotBeam * wash * exposure * 0.25h;
    colour = mix(offGlass, colour, half(lit));

    // Halo: light from the hot beam bleeding into the glass around it.
    float2 outside = max(fromCentre - halfRaster, 0.0);
    // Strongest while the beam is a hot line (wash and exposure high), fading as the picture opens.
    float halo = wash * exposure * 0.12 * exp(-outside.y / 36.0) * exp(-outside.x / 80.0);
    colour += hotBeam * halo;

    // Scanlines, static, and the hum bar rolling slowly down the picture.
    float scan = fract((glass.y + 0.5) * size.y / scanPeriod) < 0.5 ? 0.7 : 1.0;
    colour *= half(mix(1.0, scan, lit));
    colour += half((hash(floor(position) + fract(time) * 97.0) - 0.5) * noise * lit);
    float bar = fract(time * 0.11);
    colour *= half(1.0 - 0.05 * lit * smoothstep(0.08, 0.0, abs(glass.y + 0.5 - bar)));

    // Vignette towards the curved edges, and a faint reflection on the glass.
    float edge = length(glass * float2(1.0, size.y / size.x) * 2.0);
    colour *= half(1.0 - 0.45 * smoothstep(0.55, 1.15, edge));
    colour += half(0.025 * smoothstep(0.35, 0.0, length(glass - float2(-0.22, -0.28))));

    return half4(clamp(colour, 0.0h, 1.0h), 1.0h);
}
