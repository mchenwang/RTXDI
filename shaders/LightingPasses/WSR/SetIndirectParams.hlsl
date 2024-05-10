#include "../../ShaderParameters.h"

RWByteAddressBuffer u_IndirectParamsBuffer : register(u0);
RWByteAddressBuffer u_WorldSpaceReservoirStats : register(u1);

[numthreads(1, 1, 1)]
void main(uint3 GlobalIndex : SV_DispatchThreadID)
{
    uint sampleCnt = u_WorldSpaceReservoirStats.Load(0);
    // u_IndirectParamsBuffer.Store3(0, uint3(ceil(sampleCnt * 1.f / 64), 1, 1));
    uint activedGridCnt = min(u_WorldSpaceReservoirStats.Load(8), WORLD_SPACE_UPDATABLE_GRID_PER_FRAME_MAX_NUM);
    u_IndirectParamsBuffer.Store4(0, uint4(ceil(sampleCnt * 1.f / 64), 1, 1, 0));
    u_IndirectParamsBuffer.Store4(16, uint4(activedGridCnt, 1, 1, u_WorldSpaceReservoirStats.Load(4)));
}