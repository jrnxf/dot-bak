// Smooth cursor glide for Ghostty, in the spirit of monkeytype's caret.
// Written for this repo (no third-party code). Needs Ghostty 1.2+ for the
// cursor uniforms. Only the cursor is touched; every other pixel passes through.
//
// On a cursor move, a trail spans from the previous position to the new one and
// collapses onto the new cursor over DURATION seconds.

const float DURATION = 0.10;   // seconds for the glide
const float MAX_CELLS = 12.0;  // longer jumps snap instead of smearing
const float ALPHA = 0.55;      // trail opacity

// Axis-aligned box of the cursor rect at `pos` (top-left, y up) with size `size`.
bool inside(vec2 p, vec2 pos, vec2 size) {
    return p.x >= pos.x && p.x <= pos.x + size.x &&
           p.y <= pos.y && p.y >= pos.y - size.y;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    fragColor = texture(iChannel0, uv);

    float t = iTime - iTimeCursorChange;
    if (t >= DURATION) return;

    vec2 size = iCurrentCursor.zw;
    vec2 cur = iCurrentCursor.xy;
    vec2 prev = iPreviousCursor.xy;
    if (size.x <= 0.0 || size.y <= 0.0) return;

    // Snap on long jumps (scrolling, clear, window switch).
    vec2 delta = (cur - prev) / size;
    if (abs(delta.x) > MAX_CELLS || abs(delta.y) > MAX_CELLS) return;

    // Ease-out: fast start, soft landing.
    float k = clamp(t / DURATION, 0.0, 1.0);
    float e = 1.0 - (1.0 - k) * (1.0 - k) * (1.0 - k);

    // Tail leaves the old position and catches up with the new cursor.
    vec2 tail = mix(prev, cur, e);
    vec2 lo = vec2(min(tail.x, cur.x), min(tail.y, cur.y));
    vec2 hi = vec2(max(tail.x, cur.x), max(tail.y, cur.y));
    // Bounding box of head and tail rects (top-left origin, y up).
    vec2 boxPos = vec2(lo.x, hi.y);
    vec2 boxSize = size + vec2(hi.x - lo.x, hi.y - lo.y);

    if (inside(fragCoord, boxPos, boxSize) && !inside(fragCoord, cur, size)) {
        float fade = 1.0 - k;
        fragColor.rgb = mix(fragColor.rgb, iCurrentCursorColor.rgb, ALPHA * fade);
    }
}
