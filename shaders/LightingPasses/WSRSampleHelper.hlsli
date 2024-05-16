#ifndef WSR_SAMPLE_HELPERS_HLSLI
#define WSR_SAMPLE_HELPERS_HLSLI

#include "HashGridHelper.hlsli"

void StoreWorldSpaceLightSample(
    RTXDI_DIReservoir reservoir,
    RAB_LightSample lightSample,
    inout RAB_RandomSamplerState rng,
    RAB_Surface surface,
    float sceneGridScale)
{
    CacheEntry gridId;
    if (TryInsertEntry(surface.worldPos, surface.normal, surface.viewDepth, sceneGridScale, gridId))
    {
        WSRLightSample wsrLightSample = (WSRLightSample)0;
        wsrLightSample.gridId = gridId;
        wsrLightSample.lightIndex = RTXDI_GetDIReservoirLightIndex(reservoir);
        wsrLightSample.uv = RTXDI_GetDIReservoirSampleUV(reservoir);
        wsrLightSample.targetPdf = RAB_GetLightSampleTargetPdfForSurface(lightSample, surface);
        wsrLightSample.invSourcePdf = RTXDI_GetDIReservoirInvPdf(reservoir);
        wsrLightSample.random = RAB_GetNextRandom(rng);

        uint sampleCnt;
        InterlockedAdd(u_WorldSpaceGridStatsBuffer[wsrLightSample.gridId].sampleCnt, 1, sampleCnt);
        if (sampleCnt < WORLD_SPACE_LIGHT_SAMPLES_PER_GRID_MAX_NUM)
        {
            uint index;
            u_WorldSpaceReservoirStats.InterlockedAdd(0, 1, index);
            u_WorldSpaceLightSamplesBuffer[index] = wsrLightSample;
        }
    }
}

void SampleWorldSpaceReservoir(
    inout RTXDI_DIReservoir reservoir,
    inout RAB_LightSample lightSample,
    inout RAB_RandomSamplerState rng,
    RAB_Surface surface,
    float sceneGridScale,
    bool useJitter
)
{
    float3 posJitter = float3(0.f, 0.f, 0.f);
    float3 normal = surface.normal;

    if (useJitter)
    {
        float3 tangent, bitangent;
        branchlessONB(surface.normal, tangent, bitangent);
        float2 t = float2(RAB_GetNextRandom(rng), RAB_GetNextRandom(rng)) * 2.f - 1.f;
        posJitter = tangent * t.x + bitangent * t.y;
        posJitter *= sceneGridScale;
    }

    CacheEntry gridId;
    if (FindEntry(surface.worldPos + posJitter, normal, surface.viewDepth, sceneGridScale, gridId))
    {
        RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
        RAB_LightSample tempLightSample = RAB_EmptyLightSample();
        // if (RTXDI_IsValidDIReservoir(reservoir))
        {
            if (RTXDI_CombineDIReservoirs(state, reservoir, 0.5f, reservoir.targetPdf))
            {
                tempLightSample = lightSample;
            }
        }

        for (uint i = 0; i < WORLD_SPACE_RESERVOIR_NUM_PER_GRID; ++i)
        {
            uint wsReservoirIndex = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + i;
                // clamp(RAB_GetNextRandom(rng) * WORLD_SPACE_RESERVOIR_NUM_PER_GRID, 0, WORLD_SPACE_RESERVOIR_NUM_PER_GRID - 1);
            RTXDI_DIReservoir wsReservoir = RTXDI_UnpackDIReservoir(t_WorldSpaceLightReservoirs[wsReservoirIndex]);
            // wsReservoir.M = 1;
            RAB_LightSample wsLightSample = RAB_SamplePolymorphicLight(
                RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(wsReservoir), false), 
                surface, 
                RTXDI_GetDIReservoirSampleUV(wsReservoir));

            float targetPdf = 0.f;
            // if (RTXDI_IsValidDIReservoir(wsReservoir))
            {
                if (RTXDI_IsValidDIReservoir(wsReservoir))
                    targetPdf = RAB_GetLightSampleTargetPdfForSurface(wsLightSample, surface);

                if(RTXDI_CombineDIReservoirs(state, wsReservoir, RAB_GetNextRandom(rng), targetPdf))
                {
                    tempLightSample = wsLightSample;
                }
            }
        }
        RTXDI_FinalizeResampling(state, 1.0, state.M);

        reservoir = state;
        lightSample = tempLightSample;
    }
}

#endif