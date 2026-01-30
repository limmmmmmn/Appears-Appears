shader_type canvas_item;

uniform float time : hint_range(0.0, 100.0) = 0.0;
uniform int effect_type : hint_range(0, 7) = 0;
uniform vec3 color1 : source_color = vec3(0.2, 0.1, 0.3);
uniform vec3 color2 : source_color = vec3(0.4, 0.2, 0.5);

void fragment() {
    vec2 uv = UV;
    vec3 col = vec3(0.0);
    
    if (effect_type == 0) {
        // 체크무늬 스크롤
        vec2 checker = floor((uv + vec2(time * 0.1, time * 0.05)) * 8.0);
        float pattern = mod(checker.x + checker.y, 2.0);
        col = mix(color1, color2, pattern);
    }
    else if (effect_type == 1) {
        // 물결 패턴
        float wave = sin(uv.x * 10.0 + time * 2.0) * 0.5 + 0.5;
        wave *= sin(uv.y * 8.0 + time * 1.5) * 0.5 + 0.5;
        col = mix(color1, color2, wave);
    }
    else if (effect_type == 2) {
        // 방사형 소용돌이
        vec2 center = uv - 0.5;
        float dist = length(center);
        float angle = atan(center.y, center.x);
        float spiral = sin(dist * 20.0 - time * 3.0 + angle * 4.0) * 0.5 + 0.5;
        col = mix(color1, color2, spiral);
    }
    else if (effect_type == 3) {
        // 다이아몬드 패턴
        vec2 diamond = abs(fract((uv + vec2(time * 0.1)) * 6.0) - 0.5);
        float pattern = step(diamond.x + diamond.y, 0.5);
        col = mix(color1, color2, pattern);
    }
    else if (effect_type == 4) {
        // 노이즈 스크롤
        vec2 nuv = uv * 10.0 + time;
        float noise = fract(sin(dot(floor(nuv), vec2(12.9898, 78.233))) * 43758.5453);
        col = mix(color1, color2, noise);
    }
    else if (effect_type == 5) {
        // 수직 스트라이프
        float stripe = step(0.5, fract((uv.x + time * 0.2) * 10.0));
        col = mix(color1, color2, stripe);
    }
    else if (effect_type == 6) {
        // 동심원
        vec2 center = uv - 0.5;
        float dist = length(center);
        float rings = sin(dist * 30.0 - time * 4.0) * 0.5 + 0.5;
        col = mix(color1, color2, rings);
    }
    else {
        // 플라즈마
        float plasma = sin(uv.x * 10.0 + time);
        plasma += sin(uv.y * 10.0 + time * 1.2);
        plasma += sin((uv.x + uv.y) * 10.0 + time * 0.8);
        plasma = plasma / 3.0 * 0.5 + 0.5;
        col = mix(color1, color2, plasma);
    }
    
    COLOR = vec4(col, 1.0);
}
