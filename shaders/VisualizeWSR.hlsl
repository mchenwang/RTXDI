#pragma pack_matrix(row_major)

#include "ShaderParameters.h"
#include "HelperFunctions.hlsli"

RWStructuredBuffer<uint> u_GridHashMap : register(u2);
RWStructuredBuffer<uint> u_GridHashMapLockBuffer : register(u3);

#include "LightingPasses/HashGridHelper.hlsli"

ConstantBuffer<WSRVisualizationConstants> g_Const : register(b0);
Texture2D<float> t_GBufferDepth : register(t0);
Texture2D<uint> t_GBufferGeoNormals : register(t1);

RWTexture2D<float4> t_DebugColor1 : register(u0);
RWTexture2D<float4> t_DebugColor2 : register(u1);

float3 viewDepthToWorldPos(
    PlanarViewConstants view,
    int2 pixelPosition,
    float viewDepth)
{
    float2 uv = (float2(pixelPosition) + 0.5) * view.viewportSizeInv;
    float4 clipPos = float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, 0.5, 1);
    float4 viewPos = mul(clipPos, view.matClipToView);
    viewPos.xy /= viewPos.z;
    viewPos.zw = 1.0;
    viewPos.xyz *= viewDepth;
    return mul(viewPos, view.matViewToWorld).xyz;
}


float4 main(float4 i_position : SV_Position) : SV_Target
{
    int2 pixelPos = int2(i_position.xy);
    float4 result = float4(0.f, 0.f, 0.f, 1.f);
    
    pixelPos = int2(pixelPos * g_Const.resolutionScale);

    if (g_Const.visualizationMode == VIS_MODE_WS_GRID)
    {
        float viewDepth = t_GBufferDepth[pixelPos];
        float3 normal = octToNdirUnorm32(t_GBufferGeoNormals[pixelPos]);
        float3 wsPos = float3(0.f, 0.f, 0.f);
        if(viewDepth == BACKGROUND_DEPTH) return float4(0.f, 0.f, 0.f, 1.f);

        wsPos = viewDepthToWorldPos(g_Const.view, pixelPos, viewDepth);

        result.xyz = HashGridDebugColoredHash(wsPos, normal, viewDepth, g_Const.sceneGridScale);
        result.w = 1.f;
    }
    else if (g_Const.visualizationMode == VIS_MODE_ENV_VIS_DEBUG_1)
    {
        result = t_DebugColor1[pixelPos];
        if (result.w == 0.f) result = 0;
        result.w = 1.f;
        t_DebugColor1[pixelPos] = 0.f;
    }
    else if (g_Const.visualizationMode == VIS_MODE_ENV_VIS_DEBUG_2)
    {
        result = t_DebugColor2[pixelPos];
        if (result.w == 0.f) result = 0;
        result.w = 1.f;
        t_DebugColor2[pixelPos] = 0.f;
    }

    return result;
}
