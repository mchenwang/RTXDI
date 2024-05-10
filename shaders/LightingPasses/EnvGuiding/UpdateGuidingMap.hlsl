#include "../../HelperFunctions.hlsli"
#include "../../ShaderParameters.h"

StructuredBuffer<EnvRadianceData> t_EnvRandianceBuffer : register(t0);
RWByteAddressBuffer u_EnvGuidingStats : register(u0);
RWStructuredBuffer<EnvGuidingData> u_EnvGuidingMap : register(u1);
RWStructuredBuffer<EnvGuidingGridStats> u_EnvGuidingGridStatsBuffer : register(u2);

[numthreads(64, 1, 1)]
void main(uint3 GlobalIndex : SV_DispatchThreadID)
{
    if (GlobalIndex.x == 0)
    {
        u_EnvGuidingStats.Store(0, 0);
        u_EnvGuidingStats.Store(4, 0);
    }
    if (GlobalIndex.x >= WORLD_GRID_SIZE) return;

    EnvGuidingGridStats stats = u_EnvGuidingGridStatsBuffer[GlobalIndex.x];
    EnvGuidingData guidingData = u_EnvGuidingMap[GlobalIndex.x];
    

    if (guidingData.total > 0.001)
    {
        for (uint i = 0; i < ENV_GUID_RESOLUTION * ENV_GUID_RESOLUTION; ++i)
        {
            guidingData.luminance[i] *= guidingData.total;
        }
    }

    for (uint i = 0; i < min(128, stats.rayCnt); ++i)
    {
        EnvRadianceData data = t_EnvRandianceBuffer[stats.offset + i];
        if (!isnan(data.radianceLuminance) && data.radianceLuminance > 0.f)
        {
            float2 tex = EncodeConcentricOct(data.dir) * 0.5f + 0.5f;
            int2 pixel = floor(tex * float2(ENV_GUID_RESOLUTION, ENV_GUID_RESOLUTION));
            int index = pixel.x + pixel.y * ENV_GUID_RESOLUTION;
            guidingData.luminance[index] += data.radianceLuminance;
            guidingData.total += data.radianceLuminance;
        }
    }

    if (guidingData.total > 0.001)
    {
        for (uint i = 0; i < ENV_GUID_RESOLUTION * ENV_GUID_RESOLUTION; ++i)
        {
            guidingData.luminance[i] /= guidingData.total;
        }
    }
    
    u_EnvGuidingMap[GlobalIndex.x] = guidingData;
    u_EnvGuidingGridStatsBuffer[GlobalIndex.x] = (EnvGuidingGridStats)0;
}