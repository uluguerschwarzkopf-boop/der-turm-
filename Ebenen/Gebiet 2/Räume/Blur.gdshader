shader_type canvas_item;

uniform sampler2D Screen_Texture : hint_screen_texture, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 5.0) = 1.5;

void fragment() {
    vec3 result = textureLod(Screen_Texture, SCREEN_UV, blur_amount).rgb;
    COLOR.rgb = result;
}
