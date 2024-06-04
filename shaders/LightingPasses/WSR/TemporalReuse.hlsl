#pragma pack_matrix(row_major)

#include "../RtxdiApplicationBridge.hlsli"
#include <rtxdi/DIResamplingFunctions.hlsli>

#include "Helper.hlsli"

[numthreads(WORLD_SPACE_RESERVOIR_NUM_PER_GRID, 1, 1)]
void main(uint3 GlobalIndex : SV_DispatchThreadID, uint3 Gid : SV_GroupID, uint3 GTid : SV_GroupThreadID)
{
    if (Gid.x >= WORLD_SPACE_UPDATABLE_GRID_PER_FRAME_MAX_NUM) return;

    const uint iterateCnt = t_WorldSpacePassIndirectParamsBuffer.Load(12);
    RAB_RandomSamplerState rng = WSR_InitRandomSampler(uint2(Gid.x, GTid.x), iterateCnt + 11 * 13);

    uint gridId = u_WorldSpaceReservoirUpdateGridQueue[Gid.x];

    uint reservoirIndexOffset = WORLD_GRID_SIZE * WORLD_SPACE_RESERVOIR_NUM_PER_GRID;
    uint reservoirIndex = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + GTid.x;

    RAB_Surface newSurface = UnpackWSRSurface(u_WorldSpaceReservoirSurface[reservoirIndex + reservoirIndexOffset]);
    RTXDI_DIReservoir newReservoir = RTXDI_UnpackDIReservoir(u_WorldSpaceLightReservoirs[reservoirIndex + reservoirIndexOffset].packedReservoir);
    
    RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    RTXDI_CombineDIReservoirs(state, newReservoir, 0.5f, newReservoir.targetPdf);

    uint subCellIndex = GetSubCellIndex(newSurface.normal);

    WSRCellDataInGrid cellPreStats = u_WorldSpaceCellStatsBuffer[gridId];

    uint preReservoirIndexOffset = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + cellPreStats.offset[subCellIndex];
    uint reuseSamplesNum = min(cellPreStats.cnt[subCellIndex], 5);
    for (uint i = 0; i < reuseSamplesNum; ++i)
    {
        uint preReservoirIndex = clamp(RAB_GetNextRandom(rng) * cellPreStats.cnt[subCellIndex], 0, cellPreStats.cnt[subCellIndex] - 1) 
                               + preReservoirIndexOffset;
        
        RAB_Surface preSurface = UnpackWSRSurface(u_WorldSpaceReservoirSurface[preReservoirIndex]);
    // uint preReservoirIndexOffset = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID;
    // for (uint i = 0; i < 5; ++i)
    // {
    //     uint preReservoirIndex = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + //i;
    //         clamp(RAB_GetNextRandom(rng) * WORLD_SPACE_RESERVOIR_NUM_PER_GRID, 0, WORLD_SPACE_RESERVOIR_NUM_PER_GRID - 1);
        
    //     RAB_Surface preSurface = UnpackWSRSurface(u_WorldSpaceReservoirSurface[preReservoirIndex]);

        if (dot(preSurface.normal, newSurface.normal) <= 0.8f) continue;
        // if (length(preSurface.worldPos - newSurface.worldPos) >= 0.5f) continue;

        RTXDI_DIReservoir preReservoir = RTXDI_UnpackDIReservoir(u_WorldSpaceLightReservoirs[preReservoirIndex].packedReservoir);
        RAB_LightSample preLightSample = RAB_EmptyLightSample();
        
        preReservoir.M = min(preReservoir.M, newReservoir.M * 20);
        // preReservoir.M = 1;
        if (RTXDI_IsValidDIReservoir(preReservoir))
        {
            int mappedLightID = RAB_TranslateLightIndex(RTXDI_GetDIReservoirLightIndex(preReservoir), false);

            if (mappedLightID < 0)
            {
                // Kill the reservoir
                preReservoir.weightSum = 0;
                preReservoir.lightData = 0;
            }
            else
            {
                // Sample is valid - modify the light ID stored
                preReservoir.lightData = mappedLightID | RTXDI_DIReservoir_LightValidBit;
            }

            preLightSample = RAB_SamplePolymorphicLight(
                RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(preReservoir), false),
                newSurface, RTXDI_GetDIReservoirSampleUV(preReservoir));

        }

        float temporalWeight = 0.f;
        if (RTXDI_IsValidDIReservoir(preReservoir))
        {
            temporalWeight = RAB_GetLightSampleTargetPdfForSurface(preLightSample, newSurface);
        }
        RTXDI_CombineDIReservoirs(state, preReservoir, RAB_GetNextRandom(rng), temporalWeight);
    }
    RTXDI_FinalizeResampling(state, 1, state.M);

    u_WorldSpaceLightReservoirs[reservoirIndex + reservoirIndexOffset].packedReservoir = RTXDI_PackDIReservoir(state);

    // u_WorldSpaceReservoirSurface[reservoirIndex] = u_WorldSpaceReservoirSurface[reservoirIndex + reservoirIndexOffset];
    // u_WorldSpaceLightReservoirs[reservoirIndex] =  u_WorldSpaceLightReservoirs[reservoirIndex + reservoirIndexOffset];

    // if (GTid.x == 0)
    // {
    //     uint cellStatsStoreOffset = WORLD_GRID_SIZE;
    //     u_WorldSpaceCellStatsBuffer[gridId] = u_WorldSpaceCellStatsBuffer[gridId + cellStatsStoreOffset];
    // }
}