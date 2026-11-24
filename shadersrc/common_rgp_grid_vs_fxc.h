// Grid vertex shader adapted from https://bgolus.medium.com/the-best-darn-grid-shader-yet-727f9278b9d8#1e7c

#if defined(DX12)
cbuffer VertexShaderConstants : register( b0 )
{
    row_major float4x4 cViewProj : packoffset( c8 );
	float3 cAmbientCubeX [ 2 ] : packoffset ( c21 ) ;
	float3 cAmbientCubeY [ 2 ] : packoffset ( c23 ) ;
	float3 cAmbientCubeZ [ 2 ] : packoffset ( c25 ) ;
};
#else
const float4x4 cViewProj				: register(c8);

const float3 cAmbientCubeX [ 2 ] : register ( c21 );
const float3 cAmbientCubeY [ 2 ] : register ( c23 );
const float3 cAmbientCubeZ [ 2 ] : register ( c25 );
#endif

// Our default vertex data input structure
struct VS_INPUT
{
	float4 vPos : POSITION;
	float2 uv : TEXCOORD0;
};

struct VS_OUTPUT
{
    #if defined(DX11) || defined(DX12)
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
	// TOOD: Switch row-major to column-major? Then we wouldn't need this pre-processor conditional
	#if defined(DX12)
	float4 projPos = mul(cViewProj, v.vPos);
	#else
	float4 projPos = mul(v.vPos, cViewProj);
	#endif

	float gridSize = cAmbientCubeX[0].x;
	float2 offset = cAmbientCubeX[0].yz;

	VS_OUTPUT output = (VS_OUTPUT)0;
	output.projPos = projPos;
	output.uv = (v.uv.xy - 0.5) * gridSize; // do scaling from center of quad
    
	return output;
};