#if defined(DX12)
cbuffer VertexShaderConstants : register( b0 )
{
	float4 cEyePosWaterZ : packoffset( c2 );
    row_major float4x4 cViewProj : packoffset( c8 );
	float3 cAmbientCubeX [ 2 ] : packoffset ( c21 ) ;
	float3 cAmbientCubeY [ 2 ] : packoffset ( c23 ) ;
	float3 cAmbientCubeZ [ 2 ] : packoffset ( c25 ) ;
};
#else
const float4 cEyePosWaterZ				: register(c2);
const float4x4 cViewProj				: register(c8);

const float3 cAmbientCubeX [ 2 ] : register ( c21 );
const float3 cAmbientCubeY [ 2 ] : register ( c23 );
const float3 cAmbientCubeZ [ 2 ] : register ( c25 );
#endif
#define cEyePos			cEyePosWaterZ.xyz


// Our default vertex data input structure
struct VS_INPUT
{
	float4 vPos : POSITION;
	float2 uv : TEXCOORD0;
};

struct VS_OUTPUT
{
    #if defined(DX11)
	float4 projPos : SV_Position; // Screen space position
    #else
	float4 projPos : POSITION;
    #endif
	float2 uv : TEXCOORD0;		// World space position
	float depth : TEXCOORD1;
};

// The code below runs for every vertex in the model
VS_OUTPUT main(VS_INPUT v)
{
	// World space -> Screen space calculation
	#if defined(DX12)
	float4 projPos = mul(cViewProj, v.vPos);
	#else
	float4 projPos = mul(v.vPos, cViewProj);
	#endif

	float minDist = cAmbientCubeX[0].x;
	float maxDist = cAmbientCubeX[0].y;

	float dist = distance(v.vPos.xyz, cEyePos);
	float normalizedDist = (dist - minDist) / (maxDist - minDist);

	VS_OUTPUT output = (VS_OUTPUT)0;
	output.projPos = projPos;
	output.uv = v.uv.xy;
    output.depth = saturate(1.0 - normalizedDist);
    
	return output;
};