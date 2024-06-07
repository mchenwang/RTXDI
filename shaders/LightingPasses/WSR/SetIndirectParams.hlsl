#include "../../ShaderParameters.h"

RWByteAddressBuffer u_IndirectParamsBuffer : register(u0);
RWByteAddressBuffer u_WorldSpaceReservoirStats : register(u1);

[numthreads(1, 1, 1)]
void main(uint3 GlobalIndex : SV_DispatchThreadID)
{
    // uint sampleCnt = min(u_WorldSpaceReservoirStats.Load(0), WORLD_SPACE_LIGHT_SAMPLES_MAX_NUM);
    uint sampleCnt = u_WorldSpaceReservoirStats.Load(0);
    // u_IndirectParamsBuffer.Store3(0, uint3(ceil(sampleCnt * 1.f / 64), 1, 1));
    uint activedGridCnt = min(u_WorldSpaceReservoirStats.Load(8), WORLD_SPACE_UPDATABLE_GRID_PER_FRAME_MAX_NUM);

    // uint iterateCnt = (u_IndirectParamsBuffer.Load(12) + 1) % WORLD_SPACE_RESERVOIR_NUM_PER_GRID;
    uint iterateCnt = u_IndirectParamsBuffer.Load(12) + 1;
    u_IndirectParamsBuffer.Store4(0, uint4(ceil(sampleCnt * 1.f / 64), 1, 1, iterateCnt));
    u_IndirectParamsBuffer.Store4(16, uint4(activedGridCnt, 1, 1, u_WorldSpaceReservoirStats.Load(4)));
    u_IndirectParamsBuffer.Store4(32, uint4(ceil(activedGridCnt * 1.f / 64), 1, 1, 1));
}