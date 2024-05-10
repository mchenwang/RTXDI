#include "../../ShaderParameters.h"

RWStructuredBuffer<WSRGridStats> u_WorldSpaceGridStatsBuffer : register(u0);
RWByteAddressBuffer u_WorldSpaceReservoirStats : register(u1);
RWBuffer<uint> u_GridQueue : register(u2);

[numthreads(64, 1, 1)]
void main(uint3 GlobalIndex : SV_DispatchThreadID)
{
    if (GlobalIndex.x >= WORLD_GRID_SIZE) return;

	if (u_WorldSpaceGridStatsBuffer[GlobalIndex.x].sampleCnt == 0) return;
    uint sampleCnt = min(WORLD_SPACE_LIGHT_SAMPLES_PER_RESERVOIR_MAX_NUM, u_WorldSpaceGridStatsBuffer[GlobalIndex.x].sampleCnt);
    // uint sampleCnt = WORLD_SPACE_LIGHT_SAMPLES_PER_RESERVOIR_MAX_NUM;
	u_WorldSpaceReservoirStats.InterlockedAdd(4, sampleCnt, u_WorldSpaceGridStatsBuffer[GlobalIndex.x].offset);

    uint index;
    u_WorldSpaceReservoirStats.InterlockedAdd(8, 1, index);
    if (index < WORLD_SPACE_UPDATABLE_GRID_PER_FRAME_MAX_NUM)
        u_GridQueue[index] = GlobalIndex.x;

    u_WorldSpaceGridStatsBuffer[GlobalIndex.x].sampleCnt = 0;
}