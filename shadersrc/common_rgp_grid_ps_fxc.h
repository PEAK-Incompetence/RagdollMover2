// Adapted the shader code from
// https://bgolus.medium.com/the-best-darn-grid-shader-yet-727f9278b9d8#1e7c

#if defined(DX11) || defined(DX12)
cbuffer PixelShaderConstants : register( b0 )
{
	float4 LineWidth : packoffset( c0 );
};
#else
float4 LineWidth : register(c0); // (x, y, g, b)
#endif

struct PS_INPUT
{
    #if defined(DX11) || defined(DX12)
    float4 P            : SV_Position;
    #else
    float2 P            : VPOS;
    #endif
    float2 uv : TEXCOORD0;             // Position on triangle
    float depth : TEXCOORD1;
};

float4 PristineGrid(float2 uv, float2 lineWidth) 
{
    lineWidth = saturate(lineWidth);
    float4 uvDDXY = float4(ddx(uv), ddy(uv));
    float2 uvDeriv = float2(length(uvDDXY.xz), length(uvDDXY.yw));
    bool2 invertLine = lineWidth > 0.5;
    #if defined(DX12)
    float2 targetWidth = select(invertLine, 1.0 - lineWidth, lineWidth);
    #else
    float2 targetWidth = invertLine ? 1.0 - lineWidth : lineWidth;
    #endif
    float2 drawWidth = clamp(targetWidth, uvDeriv, 0.5);
    float2 lineAA = max(uvDeriv, 0.000001) * 1.5;
    float2 gridUV = abs(frac(uv) * 2.0 - 1.0);
    #if defined(DX12)
    gridUV = select(invertLine, gridUV, 1.0 - gridUV);
    #else
    gridUV = invertLine ? gridUV : 1.0 - gridUV;
    #endif
    float2 grid2 = smoothstep(drawWidth + lineAA, drawWidth - lineAA, gridUV);
    grid2 *= saturate(targetWidth / drawWidth);
    grid2 = lerp(grid2, targetWidth, saturate(uvDeriv * 2.0 - 1.0));
    #if defined(DX12)
    grid2 = select(invertLine, 1.0 - grid2, grid2);
    #else
    grid2 = invertLine ? 1.0 - grid2 : grid2;
    #endif
    return lerp(grid2.x, 1.0, grid2.y);
}

#if defined(DX11)
float4 main( PS_INPUT frag ) : SV_Target
#elif defined(DX12)
float4 main( PS_INPUT frag ) : SV_Target0
#else
float4 main( PS_INPUT frag ) : COLOR
#endif
{
    float2 _LineWidth = float2(LineWidth.x, LineWidth.y);
    half4 _LineColor = half4(1.0, 1.0, 1.0, 1.0);
    half4 _BaseColor = half4(1.0, 1.0, 1.0, 0.0);
    float grid = PristineGrid(frag.uv * 2.0 - 1.0, _LineWidth);

    float4 color = lerp(_BaseColor, _LineColor, grid * _LineColor.a);

    // Gotcha: DX11 shaderapi (v0331) requires explicit instructions for removing alpha
    if (color.a == 0.0)
    {
        discard;
    }

    // lerp between base and line color
    return color;
}