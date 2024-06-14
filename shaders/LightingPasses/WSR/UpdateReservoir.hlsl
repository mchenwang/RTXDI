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

    RAB_RandomSamplerState rng = WSR_InitRandomSampler(uint2(Gid.x, GTid.x), iterateCnt + 11 * 13);
    uint sampleCnt = stats.sampleCnt;

    uint reservoirIndex = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + GTid.x;

    uint surfaceId = clamp(floor(RAB_GetNextRandom(rng) * sampleCnt), 0, sampleCnt - 1) + stats.offset;
    RAB_Surface newSurface = UnpackWSRSurface(t_WorldSpaceReorderedLightSamplesBuffer[surfaceId].surface);
    newSurface.viewDir = normalize(g_Const.view.cameraDirectionOrPosition.xyz - newSurface.worldPos);
    RTXDI_DIReservoir newReservoir = RTXDI_EmptyDIReservoir();

    for (uint i = 0; i < WORLD_SPACE_LIGHT_SAMPLE_NUM_PER_RESERVOIR; ++i)
    {
        uint sampleIndex = clamp(floor(RAB_GetNextRandom(rng) * sampleCnt), 0, sampleCnt - 1) + stats.offset;
        
        WSRLightSample wsLightSample = t_WorldSpaceReorderedLightSamplesBuffer[sampleIndex];
        
        RAB_LightInfo lightInfo = RAB_LoadLightInfo(wsLightSample.lightIndex, false);

        RAB_LightSample lightSample = RAB_SamplePolymorphicLight(lightInfo, newSurface, wsLightSample.uv);
        
        float targetPdf = RAB_GetLightSampleTargetPdfForSurface(lightSample, newSurface);
        RTXDI_StreamSample(newReservoir, wsLightSample.lightIndex, wsLightSample.uv, RAB_GetNextRandom(rng), targetPdf, wsLightSample.invSourcePdf);
    }
    RTXDI_FinalizeResampling(newReservoir, 1.0, newReservoir.M);

    if (!(g_Const.worldSpaceReservoirFlag & WORLD_SPACE_RESERVOIR_REUSE))
    {
        u_WorldSpaceLightReservoirs[reservoirIndex].packedSurface = PackWSRSurface(newSurface);
        u_WorldSpaceLightReservoirs[reservoirIndex].packedReservoir = RTXDI_PackDIReservoir(newReservoir);
        return;
    }

    RAB_Surface surface = (RAB_Surface)0;
    RAB_Surface preSurface = UnpackWSRSurface(u_WorldSpaceLightReservoirs[reservoirIndex].packedSurface);
    preSurface.viewDir = normalize(g_Const.prevView.cameraDirectionOrPosition.xyz - preSurface.worldPos);

    RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    RTXDI_DIReservoir preReservoir = RTXDI_UnpackDIReservoir(u_WorldSpaceLightReservoirs[reservoirIndex].packedReservoir);

    preReservoir.M = min(preReservoir.M, 20 * newReservoir.M);
    RTXDI_CombineDIReservoirs(state, newReservoir, 0.5f, newReservoir.targetPdf);

    surface = newSurface;

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
    }

    RAB_LightSample preLightSample = RAB_SamplePolymorphicLight(
        RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(preReservoir), false),
        surface, RTXDI_GetDIReservoirSampleUV(preReservoir));

    float targetPdf = 0.f;
    if (RTXDI_IsValidDIReservoir(preReservoir))
    {
        targetPdf = RAB_GetLightSampleTargetPdfForSurface(preLightSample, surface);
    }
    RTXDI_CombineDIReservoirs(state, preReservoir, RAB_GetNextRandom(rng), targetPdf);
    RTXDI_FinalizeResampling(state, 1, state.M);
    
    state.age++;

    u_WorldSpaceLightReservoirs[reservoirIndex].packedSurface = PackWSRSurface(surface);
    u_WorldSpaceLightReservoirs[reservoirIndex].packedReservoir = RTXDI_PackDIReservoir(state);
}