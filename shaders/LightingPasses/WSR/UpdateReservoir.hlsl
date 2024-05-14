#include <rtxdi/RtxdiParameters.h>

#include "../../HelperFunctions.hlsli"
#include "../../ShaderParameters.h"

StructuredBuffer<WSRLightSample> t_WorldSpaceLightSamplesBuffer : register(t0);
ByteAddressBuffer t_IndirectParamsBuffer : register(t1);
RWStructuredBuffer<RTXDI_PackedDIReservoir> u_WorldSpaceLightReservoirs : register(u0);
RWStructuredBuffer<WSRGridStats> u_WorldSpaceGridStatsBuffer : register(u1);

Buffer<uint> t_GridQueue : register(t2);

#define RTXDI_ENABLE_STORE_RESERVOIR 0
#define RTXDI_LIGHT_RESERVOIR_BUFFER u_WorldSpaceLightReservoirs
#include <rtxdi/DIReservoir.hlsli>

// groupshared RTXDI_DIReservoir reservoir_cache[WORLD_SPACE_RESERVOIR_NUM_PER_GRID];

[numthreads(WORLD_SPACE_RESERVOIR_NUM_PER_GRID, 1, 1)]
void main(uint3 GlobalIndex : SV_DispatchThreadID, uint3 Gid : SV_GroupID, uint3 GTid : SV_GroupThreadID)
{
    if (Gid.x >= WORLD_SPACE_UPDATABLE_GRID_PER_FRAME_MAX_NUM) return;

    const uint maxSampleNum = t_IndirectParamsBuffer.Load(28);
    const uint iterateCnt   = t_IndirectParamsBuffer.Load(12);

    uint gridId = t_GridQueue[Gid.x];

    WSRGridStats stats = u_WorldSpaceGridStatsBuffer[gridId];

    RTXDI_DIReservoir newReservoir = RTXDI_EmptyDIReservoir();

    uint offset = GTid.x * WORLD_SPACE_LIGHT_SAMPLE_NUM_PER_RESERVOIR + stats.offset;

    float rand = 0.f;
    for (uint i = 0; i < WORLD_SPACE_LIGHT_SAMPLE_NUM_PER_RESERVOIR; ++i)
    {
        uint index = offset + i;
        if (index >= maxSampleNum) break;

        WSRLightSample lightSample = t_WorldSpaceLightSamplesBuffer[index];
        if (lightSample.gridId != gridId) break;

        rand += lightSample.random;
        RTXDI_StreamSample(newReservoir, lightSample.lightIndex, lightSample.uv, lightSample.random, lightSample.targetPdf, lightSample.invSourcePdf);
    }
    rand /= newReservoir.M;
    RTXDI_FinalizeResampling(newReservoir, 1.0, newReservoir.M);
    newReservoir.M = 1;

    RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    RTXDI_CombineDIReservoirs(state, newReservoir, 0.5f, newReservoir.targetPdf);

    uint reservoirIndex = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + ((GTid.x + iterateCnt) % WORLD_SPACE_RESERVOIR_NUM_PER_GRID);
    RTXDI_DIReservoir preReservoir = RTXDI_UnpackDIReservoir(u_WorldSpaceLightReservoirs[reservoirIndex]);
    
    if (preReservoir.age > 30)
    {
        preReservoir = RTXDI_EmptyDIReservoir();
    }
    
    float targetPdf = 0.f;
    if (RTXDI_IsValidDIReservoir(preReservoir))
        targetPdf = preReservoir.targetPdf;
    
    RTXDI_CombineDIReservoirs(state, preReservoir, rand, targetPdf);
    RTXDI_FinalizeResampling(state, 1.0, state.M);
    state.M = 1;
    state.age++;

    u_WorldSpaceLightReservoirs[reservoirIndex] = RTXDI_PackDIReservoir(state);

    // reservoir_cache[GTid.x] = state;
    // GroupMemoryBarrierWithGroupSync();

    // if (GTid.x == 0)
    // {
    //     state = RTXDI_EmptyDIReservoir();
    //     for (uint x = 0; x < WORLD_SPACE_RESERVOIR_NUM_PER_GRID; ++x)
    //     {
    //         if (RTXDI_IsValidDIReservoir(reservoir_cache[x]))
    //         {
    //             RTXDI_CombineDIReservoirs(state, reservoir_cache[x], 0.5f, reservoir_cache[x].targetPdf);
    //         }
    //     }
    //     RTXDI_FinalizeResampling(state, 1.0, state.M);
    //     state.age++;

    //     for (uint y = 0; y < WORLD_SPACE_RESERVOIR_NUM_PER_GRID; ++y)
    //     {
    //         if (RTXDI_IsValidDIReservoir(reservoir_cache[y]))
    //         {
    //             u_WorldSpaceLightReservoirs[gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + y] = RTXDI_PackDIReservoir(reservoir_cache[y]);
    //         }
    //         else
    //         {
    //             u_WorldSpaceLightReservoirs[gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + y] = RTXDI_PackDIReservoir(state);
    //         }
    //     }
    // }
}