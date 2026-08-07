// Defines cEyePos
#include "common_ps_fxc.h"

sampler BASETEXTURE : register(s0);

float4 WIDTHCOLOR : register(c0);
float4 TEXELSIZE : register(c1);

struct PS_INPUT
{
    float2 uv : TEXCOORD0;             // Position on triangle
    float depth : TEXCOORD1;
};

// Helper function for Bias
float bias(float t, float b) {
    return t / ((((1.0/b) - 2.0) * (1.0 - t)) + 1.0);
}

float4 main(PS_INPUT frag) : COLOR
{

    float2 texelSize = TEXELSIZE.zw;
    float width = WIDTHCOLOR.x;
    float4 color = float4(WIDTHCOLOR.yzw, 1);

    texelSize *= (1.0 - width);

    float4 tex = tex2D(BASETEXTURE, frag.uv);
    color.xyz *= tex.xyz;

    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            tex = tex2D(BASETEXTURE, frag.uv + texelSize * float2(x, y));
            color.a *= min(tex.a, color.a);
        } 
    }

    return color;
}