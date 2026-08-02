#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

/// Samples the already-composited panel layer through an invertible Genie
/// mapping. `progress` is 0 for the expanded panel and 1 when fully gathered
/// into the source tag.
[[ stitchable ]] half4 entryContextGenieLayer(
    float2 position,
    SwiftUI::Layer layer,
    float2 canvasSize,
    float4 panelRect,
    float4 tagRect,
    float progress
) {
    float p = saturate(progress);

    if (canvasSize.x <= 1.0 || canvasSize.y <= 1.0
        || panelRect.z <= 1.0 || panelRect.w <= 1.0
        || tagRect.z <= 1.0 || tagRect.w <= 1.0) {
        return layer.sample(position) * half(1.0 - p);
    }

    if (p <= 0.0001) {
        return layer.sample(position);
    }

    if (p >= 0.9999) {
        return half4(0.0);
    }

    // The edge attached to the tag collapses first. These two values define an
    // invertible vertical envelope, so the shader needs no per-pixel search.
    float middle = p * (1.0 - p);
    float topProgress = p * (0.82 + 0.18 * p);
    float bottomProgress = saturate(p + 0.32 * middle);

    float panelTop = panelRect.y;
    float panelBottom = panelRect.y + panelRect.w;
    float tagTop = tagRect.y;
    float tagBottom = tagRect.y + tagRect.w;

    float outputTop = mix(panelTop, tagTop, topProgress);
    float outputBottom = mix(panelBottom, tagBottom, bottomProgress);
    float outputHeight = max(1.0, outputBottom - outputTop);
    float row = (position.y - outputTop) / outputHeight;

    if (row < 0.0 || row > 1.0) {
        return half4(0.0);
    }

    // Lower rows lead the contraction, producing the lamp-like funnel instead
    // of a uniformly scaled rectangle.
    float localProgress = saturate(
        p + row * 1.35 * middle
    );
    float widthProgress = 1.0 - pow(
        max(1.0 - localProgress, 0.0),
        1.70
    );

    float panelCenterX = panelRect.x + panelRect.z * 0.5;
    float tagCenterX = tagRect.x + tagRect.z * 0.5;
    float centerX = mix(panelCenterX, tagCenterX, localProgress);

    float curve = sin(row * 3.14159265);
    centerX += curve
        * (tagCenterX - panelCenterX)
        * 0.18
        * 4.0
        * middle;

    float outputWidth = max(
        1.0,
        mix(panelRect.z, tagRect.z, widthProgress)
    );
    float outputLeft = centerX - outputWidth * 0.5;
    float column = (position.x - outputLeft) / outputWidth;

    if (column < 0.0 || column > 1.0) {
        return half4(0.0);
    }

    float2 sourcePosition = float2(
        panelRect.x + column * panelRect.z,
        panelRect.y + row * panelRect.w
    );
    half4 color = layer.sample(sourcePosition);

    // The fixed tag sits above the transition layer. Fading the final gathered
    // pixels prevents compressed panel content from bleeding through the tag.
    float terminalFade = 1.0 - smoothstep(0.84, 1.0, p);
    return color * half(terminalFade);
}

/// Search-filter variant of the Genie mapping. Unlike the entry-context
/// transition, this panel has a visible outer surface. Its rounded boundary is
/// therefore evaluated after deformation so the intermediate texture never
/// exposes its rectangular compositing bounds.
[[ stitchable ]] half4 billSearchFilterGenieLayer(
    float2 position,
    SwiftUI::Layer layer,
    float2 canvasSize,
    float4 panelRect,
    float4 tagRect,
    float progress,
    float panelCornerRadius
) {
    float p = saturate(progress);

    if (canvasSize.x <= 1.0 || canvasSize.y <= 1.0
        || panelRect.z <= 1.0 || panelRect.w <= 1.0
        || tagRect.z <= 1.0 || tagRect.w <= 1.0) {
        return half4(0.0);
    }

    if (p >= 0.9999) {
        return half4(0.0);
    }

    float middle = p * (1.0 - p);
    float topProgress = p * (0.82 + 0.18 * p);
    float bottomProgress = saturate(p + 0.32 * middle);

    float panelTop = panelRect.y;
    float panelBottom = panelRect.y + panelRect.w;
    float tagTop = tagRect.y;
    float tagBottom = tagRect.y + tagRect.w;

    float outputTop = mix(panelTop, tagTop, topProgress);
    float outputBottom = mix(panelBottom, tagBottom, bottomProgress);
    float outputHeight = max(1.0, outputBottom - outputTop);
    float row = (position.y - outputTop) / outputHeight;

    if (row < 0.0 || row > 1.0) {
        return half4(0.0);
    }

    float localProgress = saturate(p + row * 1.35 * middle);
    float widthProgress = 1.0 - pow(
        max(1.0 - localProgress, 0.0),
        1.70
    );

    float panelCenterX = panelRect.x + panelRect.z * 0.5;
    float tagCenterX = tagRect.x + tagRect.z * 0.5;
    float centerX = mix(panelCenterX, tagCenterX, localProgress);

    float curve = sin(row * 3.14159265);
    centerX += curve
        * (tagCenterX - panelCenterX)
        * 0.18
        * 4.0
        * middle;

    float outputWidth = max(1.0, mix(panelRect.z, tagRect.z, widthProgress));
    float outputLeft = centerX - outputWidth * 0.5;
    float outputRight = outputLeft + outputWidth;
    float column = (position.x - outputLeft) / outputWidth;

    if (column < 0.0 || column > 1.0) {
        return half4(0.0);
    }

    // Morph the 28-point panel corners into the source chip's capsule. The
    // radius is clamped to the current deformed envelope on every scan line.
    float tagCornerRadius = min(tagRect.z, tagRect.w) * 0.5;
    float cornerRadius = mix(panelCornerRadius, tagCornerRadius, p);
    cornerRadius = min(cornerRadius, min(outputWidth, outputHeight) * 0.5);

    float distanceToHorizontalEdge = min(
        position.y - outputTop,
        outputBottom - position.y
    );
    float cornerInset = 0.0;
    if (distanceToHorizontalEdge < cornerRadius) {
        float circleY = cornerRadius - max(distanceToHorizontalEdge, 0.0);
        cornerInset = cornerRadius - sqrt(max(
            cornerRadius * cornerRadius - circleY * circleY,
            0.0
        ));
    }

    float roundedLeft = outputLeft + cornerInset;
    float roundedRight = outputRight - cornerInset;
    float distanceToVerticalEdge = min(
        position.x - roundedLeft,
        roundedRight - position.x
    );
    if (distanceToVerticalEdge < 0.0) {
        return half4(0.0);
    }

    float2 sourcePosition = float2(
        panelRect.x + column * panelRect.z,
        panelRect.y + row * panelRect.w
    );
    half4 color = layer.sample(sourcePosition);

    float edgeAlpha = smoothstep(0.0, 1.25, distanceToVerticalEdge);
    float terminalFade = 1.0 - smoothstep(0.84, 1.0, p);
    return color * half(edgeAlpha * terminalFade);
}
