#pragma pack_matrix(row_major)

#include "../RtxdiApplicationBridge.hlsli"
#include <rtxdi/DIResamplingFunctions.hlsli>

#include "Helper.hlsli"

[numthreads(WORLD_SPACE_RESERVOIR_NUM_PER_GRID, 1, 1)]
void main(uint3 GlobalIndex : SV_DispatchThreadID, uint3 Gid : SV_GroupID, uint3 GTid : SV_GroupThreadID)
{
    if (Gid.x >= WORLD_SPACE_UPDATABLE_GRID_PER_FRAME_MAX_NUM) return;

    const uint maxSampleNum = t_WorldSpacePassIndirectParamsBuffer.Load(28);
    const uint iterateCnt   = t_WorldSpacePassIndirectParamsBuffer.Load(12);

    uint gridId = u_WorldSpaceReservoirUpdateGridQueue[Gid.x];

    WSRGridStats stats = u_WorldSpaceGridStatsBuffer[gridId];
    uint cellStatsStoreOffset = WORLD_GRID_SIZE;
    WSRCellDataInGrid cellStats = u_WorldSpaceCellStatsBuffer[gridId + cellStatsStoreOffset];

    RAB_RandomSamplerState rng = WSR_InitRandomSampler(uint2(Gid.x, GTid.x), iterateCnt + 10 * 13);
    uint sampleCnt = stats.sampleCnt;

    uint reservoirIndexOffset = WORLD_GRID_SIZE * WORLD_SPACE_RESERVOIR_NUM_PER_GRID;
    uint reservoirIndex = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + GTid.x + reservoirIndexOffset;

    // uint surfaceId = clamp(floor(RAB_GetNextRandom(rng) * sampleCnt), 0, sampleCnt - 1) + stats.offset;
    // uint packedPixelPosition = t_WorldSpaceReorderedLightSamplesBuffer[surfaceId].packedPixelPosition;
    // uint2 pixelPosition = uint2(packedPixelPosition & 0xffff, (packedPixelPosition >> 16) & 0xffff);
    // RAB_Surface newSurface = RAB_GetGBufferSurface(pixelPosition, false);
    uint surfaceStoreOffset = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID
                            + WORLD_GRID_SIZE * WORLD_SPACE_RESERVOIR_NUM_PER_GRID;
    // uint surfaceStoreOffset = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID;
    WSRSurfaceData wsrSurface = u_WorldSpaceReservoirSurface[GTid.x + surfaceStoreOffset];
    RAB_Surface newSurface = UnpackWSRSurface(wsrSurface);
    newSurface.viewDir = normalize(g_Const.view.cameraDirectionOrPosition.xyz - newSurface.worldPos);

    RTXDI_DIReservoir newReservoir = RTXDI_EmptyDIReservoir();

    for (uint i = 0; i < WORLD_SPACE_LIGHT_SAMPLE_NUM_PER_RESERVOIR; ++i)
    {
        uint sampleIndex = clamp(floor(RAB_GetNextRandom(rng) * sampleCnt), 0, sampleCnt - 1) + stats.offset;
    // for (uint i = 0; i < sampleCnt; ++i)
    // {
    //     uint sampleIndex = i + stats.offset;
        
        WSRLightSample wsLightSample = t_WorldSpaceReorderedLightSamplesBuffer[sampleIndex];
        
        RAB_LightInfo lightInfo = RAB_LoadLightInfo(wsLightSample.lightIndex, false);

        RAB_LightSample lightSample = RAB_SamplePolymorphicLight(lightInfo, newSurface, wsLightSample.uv);
        
        float targetPdf = RAB_GetLightSampleTargetPdfForSurface(lightSample, newSurface);
        RTXDI_StreamSample(newReservoir, wsLightSample.lightIndex, wsLightSample.uv, RAB_GetNextRandom(rng), targetPdf, wsLightSample.invSourcePdf);
    }
    RTXDI_FinalizeResampling(newReservoir, 1.0, newReservoir.M);

    u_WorldSpaceReservoirSurface[reservoirIndex] = PackWSRSurface(newSurface);
    u_WorldSpaceLightReservoirs[reservoirIndex].packedReservoir = RTXDI_PackDIReservoir(newReservoir);
    return;

    // {
    //     RAB_Surface surface = (RAB_Surface)0;
    //     RAB_Surface preSurface = UnpackWSRSurface(u_WorldSpaceReservoirSurface[reservoirIndex]);

    //     RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    //     RTXDI_DIReservoir preReservoir = RTXDI_UnpackDIReservoir(u_WorldSpaceLightReservoirs[reservoirIndex].packedReservoir);

    //     // preReservoir.M = min(preReservoir.M, 20 * newReservoir.M);
    //     {
    //         {
    //             RTXDI_CombineDIReservoirs(state, newReservoir, 0.5f, newReservoir.targetPdf);

    //             surface = newSurface;

    //             RAB_LightSample preLightSample = RAB_SamplePolymorphicLight(
    //                 RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(preReservoir), false),
    //                 surface, RTXDI_GetDIReservoirSampleUV(preReservoir));

    //             bool selected = false;
    //             float targetPdf = RAB_GetLightSampleTargetPdfForSurface(preLightSample, surface);
    //             if(RTXDI_CombineDIReservoirs(state, preReservoir, RAB_GetNextRandom(rng), targetPdf))
    //             {
    //                 selected = true;
    //             }
    //         }
    //         RTXDI_FinalizeResampling(state, 1, state.M);
    //     }
        
    //     state.age++;

    //     u_WorldSpaceReservoirSurface[reservoirIndex] = PackWSRSurface(surface);
    //     u_WorldSpaceLightReservoirs[reservoirIndex].packedReservoir = RTXDI_PackDIReservoir(state);
    //     return;
    // }
}