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

    uint offset = GTid.x * 32 + stats.offset;

    float rand = 0.f;
    for (uint i = 0; i < 32; ++i)
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
    // newReservoir.M = 1;

    RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    RTXDI_CombineDIReservoirs(state, newReservoir, 0.f, newReservoir.targetPdf);
    // if (RTXDI_IsValidDIReservoir(newReservoir))
    // {
    //     state = newReservoir;
    //     // RTXDI_CombineDIReservoirs(state, newReservoir, 0.f, newReservoir.targetPdf);
    // }

    uint reservoirIndex = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + ((GTid.x + iterateCnt) % WORLD_SPACE_RESERVOIR_NUM_PER_GRID);
    RTXDI_DIReservoir preState = RTXDI_UnpackDIReservoir(u_WorldSpaceLightReservoirs[reservoirIndex]);
    if (RTXDI_IsValidDIReservoir(state) /*&& preState.age < 20*/)
    {
        if (preState.age < 30)
        {
            uint preStateLimitNum = 20 * state.M;
            if (preState.M > preStateLimitNum) {
                preState.M = preStateLimitNum;
            }
            RTXDI_CombineDIReservoirs(state, preState, rand, preState.targetPdf);
            state.age++;
        }
        RTXDI_FinalizeResampling(state, 1.0, state.M);
    }
    else state = preState;

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