#include "../../ShaderParameters.h"

ByteAddressBuffer t_WorldSpaceReservoirStats : register(t0);
StructuredBuffer<WSRLightSample> t_WorldSpaceLightSamplesBuffer : register(t1);
RWStructuredBuffer<WSRGridStats> u_WorldSpaceGridStatsBuffer : register(u0);
RWStructuredBuffer<WSRLightSample> u_OrederedWorldSpaceLightSamplesBuffer : register(u1);

[numthreads(64, 1, 1)]
void main(uint3 GlobalIndex : SV_DispatchThreadID)
{
    // const uint num = min(t_WorldSpaceReservoirStats.Load(0), WORLD_SPACE_LIGHT_SAMPLES_MAX_NUM);
    const uint num = t_WorldSpaceReservoirStats.Load(0);
    if (GlobalIndex.x >= num) return;

    WSRLightSample data = t_WorldSpaceLightSamplesBuffer[GlobalIndex.x];
    
    uint index;
    InterlockedAdd(u_WorldSpaceGridStatsBuffer[data.gridId].sampleCnt, 1, index);
    if (index < WORLD_SPACE_LIGHT_SAMPLES_PER_GRID_MAX_NUM)
        u_OrederedWorldSpaceLightSamplesBuffer[u_WorldSpaceGridStatsBuffer[data.gridId].offset + index] = data;
}