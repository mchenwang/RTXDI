#pragma pack_matrix(row_major)

#include "../RtxdiApplicationBridge.hlsli"
#include <rtxdi/DIResamplingFunctions.hlsli>

#include "Helper.hlsli"

groupshared uint gs_surfaceCntInCell[WORLD_GRID_SUB_CELL_NUM];
groupshared WSRCellDataInGrid gs_cellStats;

[numthreads(WORLD_SPACE_RESERVOIR_NUM_PER_GRID, 1, 1)]
void main(uint3 GlobalIndex : SV_DispatchThreadID, uint3 Gid : SV_GroupID, uint3 GTid : SV_GroupThreadID)
{
    return;
    if (Gid.x >= WORLD_SPACE_UPDATABLE_GRID_PER_FRAME_MAX_NUM) return;

    if (GTid.x == 0)
    {
        [unroll]
        for (uint i = 0; i < WORLD_GRID_SUB_CELL_NUM; i++)
            gs_surfaceCntInCell[i] = 0;
    }
    GroupMemoryBarrierWithGroupSync();

    const uint iterateCnt = t_WorldSpacePassIndirectParamsBuffer.Load(12);

    uint gridId = u_WorldSpaceReservoirUpdateGridQueue[Gid.x];

    WSRGridStats stats = u_WorldSpaceGridStatsBuffer[gridId];

    RAB_RandomSamplerState rng = WSR_InitRandomSampler(uint2(Gid.x, GTid.x), iterateCnt + 9 * 13);
    uint sampleCnt = stats.sampleCnt;

    uint surfaceId = clamp(floor(RAB_GetNextRandom(rng) * sampleCnt), 0, sampleCnt - 1) + stats.offset;
    uint packedPixelPosition = t_WorldSpaceReorderedLightSamplesBuffer[surfaceId].packedPixelPosition;
    uint2 pixelPosition = uint2(packedPixelPosition & 0xffff, (packedPixelPosition >> 16) & 0xffff);
    RAB_Surface surface = RAB_GetGBufferSurface(pixelPosition, false);
    WSRSurfaceData  wsrSurface = PackWSRSurface(surface);
    
    float3 surfaceNormal = octToNdirUnorm32(wsrSurface.normal);
    
    uint subCellIndex = GetSubCellIndex(surfaceNormal);

    InterlockedAdd(gs_surfaceCntInCell[subCellIndex], 1);

    GroupMemoryBarrierWithGroupSync();
    if (GTid.x == 0)
    {
        gs_cellStats = (WSRCellDataInGrid)0;
        uint offset = 0;
        for (uint i = 0; i < WORLD_GRID_SUB_CELL_NUM; i++)
        {
            // cellStats.cnt[i] = gs_surfaceCntInCell[i];
            gs_cellStats.offset[i] = offset;
            offset += gs_surfaceCntInCell[i];
        }
    }
    GroupMemoryBarrierWithGroupSync();

    uint surfaceStoreIndex;
    InterlockedAdd(gs_cellStats.cnt[subCellIndex], 1, surfaceStoreIndex);

    uint surfaceStoreOffset = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID
                            + gs_cellStats.offset[subCellIndex]
                            + WORLD_GRID_SIZE * WORLD_SPACE_RESERVOIR_NUM_PER_GRID;
    u_WorldSpaceReservoirSurface[surfaceStoreIndex + surfaceStoreOffset] = wsrSurface;

    if (GTid.x == 0)
    {
        uint cellStatsStoreOffset = WORLD_GRID_SIZE;
        u_WorldSpaceCellStatsBuffer[gridId + cellStatsStoreOffset] = gs_cellStats;
    }
}