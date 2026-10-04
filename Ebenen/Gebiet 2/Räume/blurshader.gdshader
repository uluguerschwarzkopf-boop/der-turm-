shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 5.0) = 1.5;

void fragment() {
    vec4 c = textureLod(screen_tex, SCREEN_UV, blur_amount);
    if (c.a > 0.0001) {
        c.rgb /= c.a;
    }
    COLOR *= c; 
}
