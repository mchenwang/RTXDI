#pragma pack_matrix(row_major)

#include "../RtxdiApplicationBridge.hlsli"
#include <rtxdi/DIResamplingFunctions.hlsli>

#include "Helper.hlsli"

[numthreads(WORLD_SPACE_RESERVOIR_NUM_PER_GRID, 1, 1)]
void main(uint3 GlobalIndex : SV_DispatchThreadID, uint3 Gid : SV_GroupID, uint3 GTid : SV_GroupThreadID)
{
    if (Gid.x >= WORLD_SPACE_UPDATABLE_GRID_PER_FRAME_MAX_NUM) return;

    const uint iterateCnt = t_WorldSpacePassIndirectParamsBuffer.Load(12);

    uint gridId = u_WorldSpaceReservoirUpdateGridQueue[Gid.x];

    WSRGridStats stats = u_WorldSpaceGridStatsBuffer[gridId];

    RAB_RandomSamplerState rng = WSR_InitRandomSampler(uint2(Gid.x, GTid.x), iterateCnt + 10 * 13);
    uint sampleCnt = stats.sampleCnt;

    uint reservoirIndexOffset = WORLD_GRID_SIZE * WORLD_SPACE_RESERVOIR_NUM_PER_GRID;
    uint reservoirIndex = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + reservoirIndexOffset + GTid.x;

    uint surfaceId = clamp(floor(RAB_GetNextRandom(rng) * sampleCnt), 0, sampleCnt - 1) + stats.offset;
    uint packedPixelPosition = t_WorldSpaceReorderedLightSamplesBuffer[surfaceId].packedPixelPosition;
    uint2 pixelPosition = uint2(packedPixelPosition & 0xffff, (packedPixelPosition >> 16) & 0xffff);
    RAB_Surface newSurface = RAB_GetGBufferSurface(pixelPosition, false);
    RTXDI_DIReservoir newReservoir = RTXDI_EmptyDIReservoir();
    
    uint sampleNum = min(WORLD_SPACE_LIGHT_SAMPLE_NUM_PER_RESERVOIR, sampleCnt / 4);
    for (uint i = 0; i < sampleNum; ++i)
    {
        uint sampleIndex = clamp(floor(RAB_GetNextRandom(rng) * sampleCnt), 0, sampleCnt - 1) + stats.offset;
        
        WSRLightSample wsLightSample = t_WorldSpaceReorderedLightSamplesBuffer[sampleIndex];

        // RTXDI_DIReservoir neighborReservoir = RTXDI_UnpackDIReservoir(wsLightSample.packedReservoir);
        // RAB_LightSample neighborLightSample = RAB_EmptyLightSample();
        // float neighborWeight = 0.f;
        
        // if (RTXDI_IsValidDIReservoir(neighborReservoir))
        // {
        //     neighborLightSample = RAB_SamplePolymorphicLight(
        //         RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(neighborReservoir), false),
        //         newSurface, RTXDI_GetDIReservoirSampleUV(neighborReservoir));

        //     neighborWeight = RAB_GetLightSampleTargetPdfForSurface(neighborLightSample, newSurface);
        // }

        // RTXDI_CombineDIReservoirs(newReservoir, neighborReservoir, RAB_GetNextRandom(rng), neighborWeight);
        
        RAB_LightInfo lightInfo = RAB_LoadLightInfo(wsLightSample.lightIndex, false);

        RAB_LightSample lightSample = RAB_SamplePolymorphicLight(lightInfo, newSurface, wsLightSample.uv);
        
        float targetPdf = RAB_GetLightSampleTargetPdfForSurface(lightSample, newSurface);
        RTXDI_StreamSample(newReservoir, wsLightSample.lightIndex, wsLightSample.uv, RAB_GetNextRandom(rng), targetPdf, wsLightSample.invSourcePdf);
    }
    RTXDI_FinalizeResampling(newReservoir, 1.0, newReservoir.M);

    u_WorldSpaceReservoirSurface[reservoirIndex] = PackWSRSurface(newSurface);
    u_WorldSpaceLightReservoirs[reservoirIndex].packedReservoir = RTXDI_PackDIReservoir(newReservoir);
    return;
}