#include "../../ShaderParameters.h"

ByteAddressBuffer t_EnvGuidingStats : register(t0);
StructuredBuffer<EnvRadianceData> t_UnorederedEnvRandianceBuffer : register(t1);
RWStructuredBuffer<EnvGuidingGridStats> u_EnvGuidingGridStatsBuffer : register(u0);
RWStructuredBuffer<EnvRadianceData> u_OrederedEnvRandianceBuffer : register(u1);

[numthreads(64, 1, 1)]
void main(uint3 GlobalIndex : SV_DispatchThreadID)
{
    const uint num = min(t_EnvGuidingStats.Load(0), ENV_GUID_MAX_TEMP_RAY_NUM);
    if (GlobalIndex.x >= num) return;

    EnvRadianceData data = t_UnorederedEnvRandianceBuffer[GlobalIndex.x];
    
    uint index;
    InterlockedAdd(u_EnvGuidingGridStatsBuffer[data.gridId].rayCnt, 1, index);
    if (index < 128)
        u_OrederedEnvRandianceBuffer[u_EnvGuidingGridStatsBuffer[data.gridId].offset + index] = data;
}