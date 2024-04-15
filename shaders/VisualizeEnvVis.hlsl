#pragma pack_matrix(row_major)

#include "ShaderParameters.h"
#include "HelperFunctions.hlsli"
#include "LightingPasses/EnvVisibilityGuid.hlsli"

ConstantBuffer<EnvVisibilityVisualizationConstants> g_Const : register(b0);
Texture2D<float> t_GBufferDepth : register(t0);
Texture2D<uint> t_GBufferNormals : register(t1);

StructuredBuffer<EnvVisibilityMapData> t_EnvVisiblityDataMap : register(t2);
Buffer<float> t_EnvVisiblityCdfMap : register(t3);

RWTexture2D<float4> t_DebugColor1 : register(u0);
RWTexture2D<float4> t_DebugColor2 : register(u1);

static const uint s_random_colors_size = 11;
static const float3 s_random_colors[s_random_colors_size] = {
	float3(0,0,1),
	float3(0,1,1),
	float3(0,1,0),
	float3(1,1,0),
	float3(1,0,0),
	float3(1,0,1),
	float3(0.5,1,1),
	float3(0.5,1,0.5),
	float3(1,1,0.5),
	float3(1,0.5,0.5),
	float3(1,0.5,1),
};
float3 GetRandomColor(uint index)
{
	return s_random_colors[index % s_random_colors_size];
}


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
        float3 wsPos = float3(0.f, 0.f, 0.f);
        if(viewDepth == BACKGROUND_DEPTH) return float4(0.f, 0.f, 0.f, 1.f);

        wsPos = viewDepthToWorldPos(g_Const.view, pixelPos, viewDepth);

        uint hashId = GetUniformGridCellHashId(wsPos);

        // result = float4(wsPos, 1.f);

        result = float4(GetRandomColor(hashId), 1.f);
    }
    else if (g_Const.visualizationMode == VIS_MODE_ENV_VIS_MAP)
    {
        int2 map_id = floor(float2(pixelPos.x / ENV_VISIBILITY_RESOLUTION, pixelPos.y / ENV_VISIBILITY_RESOLUTION));
        uint map_index = map_id.x + map_id.y * ENV_GUID_GRID_DIMENSIONS * ENV_GUID_GRID_DIMENSIONS;
        int2 inner_id = pixelPos % ENV_VISIBILITY_RESOLUTION;
        uint inner_index = inner_id.x + inner_id.y * ENV_VISIBILITY_RESOLUTION;

        if (t_EnvVisiblityDataMap[map_index].total_cnt > 0)
            result = t_EnvVisiblityDataMap[map_index].local_cnt[inner_index] * 1.f / t_EnvVisiblityDataMap[map_index].total_cnt;
            // result = t_EnvVisiblityDataMap[map_index].local_cnt[inner_index];
            // result = t_EnvVisiblityCdfMap[map_index * 36 + inner_index];

        result.w = 1.f;
    }
    else if (g_Const.visualizationMode == VIS_MODE_WS_ENV_VIS_MAP)
    {
        float viewDepth = t_GBufferDepth[pixelPos];
        float3 normal = octToNdirUnorm32(t_GBufferNormals[pixelPos]);
        float3 wsPos = float3(0.f, 0.f, 0.f);
        if(viewDepth == BACKGROUND_DEPTH) return float4(0.f, 0.f, 0.f, 1.f);

        wsPos = viewDepthToWorldPos(g_Const.view, pixelPos, viewDepth);

        uint hashId = GetUniformGridCellHashId(wsPos);

        float3 grid_bottom_center = GetUniformGridCell(wsPos, 0.5f) + float3(0.5f, -0.1f, 0.5f);

        float3 dir = normalize(wsPos * 2.f - (grid_bottom_center));

        float3 tangent, bitangent;
        branchlessONB(normal, tangent, bitangent);
        float3 dirLocal = float3(dot(dir, tangent), dot(dir, bitangent), dot(dir, normal));
        uint pixelIndex = GetInnerPixelIndexBySmeiSphereTexcoord(GetSmeiSphereTexcoord(dirLocal));

        float pdf = 0.f;
        if (t_EnvVisiblityDataMap[hashId].total_cnt > 0)
            pdf = t_EnvVisiblityDataMap[hashId].local_cnt[pixelIndex] * 1.f / t_EnvVisiblityDataMap[hashId].total_cnt;

        result.xyz = float3(pdf, pdf, pdf);
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
        else result.xyz = result.xyz * 0.5f + 0.5f;
        result.w = 1.f;
        t_DebugColor2[pixelPos] = 0.f;
    }

    return result;
}
