
#if defined(DX11)
Texture2D BaseTexture : register(t0);
SamplerState _BaseSampler : register(s0);
#else
sampler BaseTexture : register(s0);
#endif

float4 WidthColor : register(c0); // (width, r, g, b)
float4 TexelSize : register(c1); // (width, height, 1/width, 1/height)

struct PS_INPUT
{
    #if defined(DX11)
    float4 P            : SV_Position;
    #else
    float2 P            : VPOS;
    #endif
    float2 uv : TEXCOORD0;             // Position on triangle
    float depth : TEXCOORD1;
};

// Helper function for Bias
float bias(float t, float b) {
    return t / ((((1.0/b) - 2.0) * (1.0 - t)) + 1.0);
}

float4 sampleBase(float2 uv) {
    float4 tex;
    #if defined(DX11)
    tex = BaseTexture.Sample(_BaseSampler, uv);
    #else
    tex = tex2D(BaseTexture, uv);
    #endif
    return tex;
}

#if defined(DX11)
float4 main( PS_INPUT frag ) : SV_Target
#else
float4 main( PS_INPUT frag ) : COLOR
#endif
{
    float2 texelSize = TexelSize.zw;
    float width = WidthColor.x;
    float4 color = float4(WidthColor.yzw, 1);

    texelSize *= (1.0 - width);

    float4 tex = sampleBase(frag.uv);
    color.xyz *= tex.xyz;

    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            tex = sampleBase(frag.uv + texelSize * float2(x, y));
            color.a *= min(tex.a, color.a);
        } 
    }

    // Gotcha: DX11 shaderapi (v0331) requires explicit instructions for removing alpha
    if (color.a == 0.0)
    {
        discard;
    }

    return color;
}