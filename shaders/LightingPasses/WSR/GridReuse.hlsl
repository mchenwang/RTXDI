#pragma pack_matrix(row_major)

#include "../RtxdiApplicationBridge.hlsli"
#include <rtxdi/DIResamplingFunctions.hlsli>

#include "Helper.hlsli"

static const int3 s_neighbor[26] =
{
    int3(-1,  0,  0),
    int3(-1, -1,  0),
    int3(-1,  0, -1),
    int3(-1,  1,  0),
    int3(-1,  0,  1),
    int3(-1, -1, -1),
    int3(-1,  1, -1),
    int3(-1, -1,  1),
    int3(-1,  1,  1),

    // int3( 0,  0,  0),
    int3( 0, -1,  0),
    int3( 0,  0, -1),
    int3( 0,  1,  0),
    int3( 0,  0,  1),
    int3( 0, -1, -1),
    int3( 0,  1, -1),
    int3( 0, -1,  1),
    int3( 0,  1,  1),

    int3( 1,  0,  0),
    int3( 1, -1,  0),
    int3( 1,  0, -1),
    int3( 1,  1,  0),
    int3( 1,  0,  1),
    int3( 1, -1, -1),
    int3( 1,  1, -1),
    int3( 1, -1,  1),
    int3( 1,  1,  1),
};

[numthreads(WORLD_SPACE_RESERVOIR_NUM_PER_GRID, 1, 1)]
void main(uint3 GlobalIndex : SV_DispatchThreadID, uint3 Gid : SV_GroupID, uint3 GTid : SV_GroupThreadID)
{
    if (Gid.x >= WORLD_SPACE_UPDATABLE_GRID_PER_FRAME_MAX_NUM) return;
    uint gridId = u_WorldSpaceReservoirUpdateGridQueue[Gid.x];

    uint reservoirIndexOffset = WORLD_GRID_SIZE * WORLD_SPACE_RESERVOIR_NUM_PER_GRID;
    uint reservoirIndex = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + GTid.x;
    uint cellStatsStoreOffset = WORLD_GRID_SIZE;

    if (!(g_Const.worldSpaceReservoirFlag & WORLD_SPACE_RESERVOIR_GRID_REUSE))
    {
        u_WorldSpaceReservoirSurface[reservoirIndex] = u_WorldSpaceReservoirSurface[reservoirIndex + reservoirIndexOffset];
        u_WorldSpaceLightReservoirs[reservoirIndex] = u_WorldSpaceLightReservoirs[reservoirIndex + reservoirIndexOffset];

        if (GTid.x == 0)
        {
            u_WorldSpaceCellStatsBuffer[gridId] = u_WorldSpaceCellStatsBuffer[gridId + cellStatsStoreOffset];
        }

        return;
    }

    const uint iterateCnt = t_WorldSpacePassIndirectParamsBuffer.Load(12);
    RAB_RandomSamplerState rng = WSR_InitRandomSampler(uint2(Gid.x, GTid.x), iterateCnt + 12 * 13);

    RAB_Surface surface = UnpackWSRSurface(u_WorldSpaceReservoirSurface[reservoirIndex + reservoirIndexOffset]);
    RTXDI_DIReservoir reservoir = RTXDI_UnpackDIReservoir(u_WorldSpaceLightReservoirs[reservoirIndex + reservoirIndexOffset].packedReservoir);

    RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    RTXDI_CombineDIReservoirs(state, reservoir, 0.5f, reservoir.targetPdf);

    WSRGridStats stats = u_WorldSpaceGridStatsBuffer[gridId];
    uint currentLevel = stats.gridLevel;
    int3 gridPosition = CalculateGridPosition(surface.worldPos, currentLevel, g_Const.sceneGridScale);

    for (int i = 0; i < 26; i++)
    {
        int3 neighborPosition = gridPosition + s_neighbor[i];

        HashKey neighborHash = ComputeSpatialHash(neighborPosition, surface.normal, currentLevel);
        CacheEntry hashEntry = 0;
        if (FindEntry(neighborHash, hashEntry))
        {
            uint neighborGridId = hashEntry.x;
            uint subCellIndex = hashEntry.y;

            WSRCellDataInGrid neighborGridCellStats = u_WorldSpaceCellStatsBuffer[neighborGridId + cellStatsStoreOffset];

            if (neighborGridCellStats.cnt[subCellIndex] > 0)
            {
                uint neighborReservoirIndexOffset = reservoirIndexOffset + gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + neighborGridCellStats.offset[subCellIndex];
                uint reuseSamplesNum = min(neighborGridCellStats.cnt[subCellIndex], 100);
                for (uint i = 0; i < reuseSamplesNum; ++i)
                {
                    uint neighborReservoirIndex = clamp(RAB_GetNextRandom(rng) * neighborGridCellStats.cnt[subCellIndex], 
                                                        0, neighborGridCellStats.cnt[subCellIndex] - 1) 
                                                + neighborReservoirIndexOffset;
                    
                    RAB_Surface neighborSurface = UnpackWSRSurface(u_WorldSpaceReservoirSurface[neighborReservoirIndex]);
                    if (dot(neighborSurface.normal, surface.normal) <= 0.8f) continue;

                    RTXDI_DIReservoir neighborReservoir = RTXDI_UnpackDIReservoir(u_WorldSpaceLightReservoirs[neighborReservoirIndex].packedReservoir);
                    RAB_LightSample neighborLightSample = RAB_EmptyLightSample();
                    float neighborWeight = 0.f;
                    
                    if (RTXDI_IsValidDIReservoir(neighborReservoir))
                    {
                        neighborLightSample = RAB_SamplePolymorphicLight(
                            RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(neighborReservoir), false),
                            surface, RTXDI_GetDIReservoirSampleUV(neighborReservoir));

                        neighborWeight = RAB_GetLightSampleTargetPdfForSurface(neighborLightSample, surface);
                    }

                    RTXDI_CombineDIReservoirs(state, neighborReservoir, RAB_GetNextRandom(rng), neighborWeight);
                }
            }
        }
    }
    RTXDI_FinalizeResampling(state, 1, state.M);

    // if (Find)

    u_WorldSpaceReservoirSurface[reservoirIndex] = u_WorldSpaceReservoirSurface[reservoirIndex + reservoirIndexOffset];
    u_WorldSpaceLightReservoirs[reservoirIndex].packedReservoir = RTXDI_PackDIReservoir(state);

    if (GTid.x == 0)
    {
        uint cellStatsStoreOffset = WORLD_GRID_SIZE;
        u_WorldSpaceCellStatsBuffer[gridId] = u_WorldSpaceCellStatsBuffer[gridId + cellStatsStoreOffset];
    }
}