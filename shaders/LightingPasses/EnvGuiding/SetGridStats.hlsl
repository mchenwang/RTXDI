#include "../../ShaderParameters.h"

// cbuffer cb : register(b0)
// {
//     uint g_SetFlag;
// };
RWStructuredBuffer<EnvGuidingGridStats> u_EnvGuidingGridStatsBuffer : register(u0);
RWByteAddressBuffer u_EnvGuidingStats : register(u1);

[numthreads(64, 1, 1)]
void main(uint3 GlobalIndex : SV_DispatchThreadID)
{
    if (GlobalIndex.x >= WORLD_GRID_SIZE) return;
    // if (g_SetFlag == 1)
    // {
    //     u_EnvGuidingGridStatsBuffer[GlobalIndex.x].rayCnt = 0;
    //     u_EnvGuidingGridStatsBuffer[GlobalIndex.x].offset = 0;
    //     return;
    // }

	if (u_EnvGuidingGridStatsBuffer[GlobalIndex.x].rayCnt == 0) return;
    uint rayCnt = min(128, u_EnvGuidingGridStatsBuffer[GlobalIndex.x].rayCnt);
	u_EnvGuidingStats.InterlockedAdd(4, rayCnt, u_EnvGuidingGridStatsBuffer[GlobalIndex.x].offset);
    u_EnvGuidingGridStatsBuffer[GlobalIndex.x].rayCnt = 0;
}