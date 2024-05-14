/***************************************************************************
 # Copyright (c) 2020-2023, NVIDIA CORPORATION.  All rights reserved.
 #
 # NVIDIA CORPORATION and its licensors retain all intellectual property
 # and proprietary rights in and to this software, related documentation
 # and any modifications thereto.  Any use, reproduction, disclosure or
 # distribution of this software and related documentation without an express
 # license agreement from NVIDIA CORPORATION is strictly prohibited.
 **************************************************************************/

#pragma pack_matrix(row_major)

#include "RtxdiApplicationBridge.hlsli"

#include <rtxdi/InitialSamplingFunctions.hlsli>
#include <rtxdi/DIResamplingFunctions.hlsli>

#ifdef WITH_NRD
#define NRD_HEADER_ONLY
#include <NRD.hlsli>
#endif

#include "ShadingHelpers.hlsli"
#include "HashGridHelper.hlsli"

#if USE_RAY_QUERY
[numthreads(RTXDI_SCREEN_SPACE_GROUP_SIZE, RTXDI_SCREEN_SPACE_GROUP_SIZE, 1)]
void main(uint2 GlobalIndex : SV_DispatchThreadID)
#else
[shader("raygeneration")]
void RayGen()
#endif
{
#if !USE_RAY_QUERY
    uint2 GlobalIndex = DispatchRaysIndex().xy;
#endif
    uint2 pixelPosition = RTXDI_ReservoirPosToPixelPos(GlobalIndex, g_Const.runtimeParams.activeCheckerboardField);

    RAB_Surface surface = RAB_GetGBufferSurface(pixelPosition, false);

    if (!RAB_IsSurfaceValid(surface))
        return;

    RAB_RandomSamplerState rng = RAB_InitRandomSampler(GlobalIndex, 5);
    RAB_RandomSamplerState tileRng = RAB_InitRandomSampler(GlobalIndex / RTXDI_TILE_SIZE_IN_PIXELS, 1);

    RTXDI_SampleParameters sampleParams = RTXDI_InitSampleParameters(
        g_Const.restirDI.initialSamplingParams.numPrimaryLocalLightSamples,
        g_Const.restirDI.initialSamplingParams.numPrimaryInfiniteLightSamples,
        g_Const.restirDI.initialSamplingParams.numPrimaryEnvironmentSamples,
        g_Const.restirDI.initialSamplingParams.numPrimaryBrdfSamples,
        g_Const.restirDI.initialSamplingParams.brdfCutoff,
        0.001f);

    RAB_LightSample lightSample = RAB_EmptyLightSample();
    RTXDI_DIReservoir reservoir = RTXDI_EmptyDIReservoir();

    if ((g_Const.worldSpaceReservoirFlag & WORLD_SPACE_RESERVOIR_DI_COMBINE) || 
        (!(g_Const.worldSpaceReservoirFlag & WORLD_SPACE_RESERVOIR_DI_ENABLE)))
        reservoir = RTXDI_SampleLightsForSurface(rng, tileRng, surface,
            sampleParams, g_Const.lightBufferParams, g_Const.restirDI.initialSamplingParams.localLightSamplingMode,
    #if RTXDI_ENABLE_PRESAMPLING
            g_Const.localLightsRISBufferSegmentParams, g_Const.environmentLightRISBufferSegmentParams,
    #if RTXDI_REGIR_MODE != RTXDI_REGIR_MODE_DISABLED
            g_Const.regir,
    #endif
    #endif
            lightSample);

    if (g_Const.worldSpaceReservoirFlag & WORLD_SPACE_RESERVOIR_DI_ENABLE)
    {
        float3 posJitter = float3(0.f, 0.f, 0.f);
        float3 normal = surface.normal;

        if (g_Const.worldSpaceReservoirFlag & WORLD_SPACE_RESERVOIR_SAMPLE_WITH_JITTER)
        {
            float3 tangent, bitangent;
            branchlessONB(surface.normal, tangent, bitangent);
            float2 t = float2(RAB_GetNextRandom(rng), RAB_GetNextRandom(rng)) * 2.f - 1.f;
            posJitter = tangent * t.x + bitangent * t.y;
            posJitter *= g_Const.sceneGridScale;
        }
    
        CacheEntry gridId;
        if (FindEntry(surface.worldPos + posJitter, normal, surface.viewDepth, g_Const.sceneGridScale, gridId))
        {
            RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
            RAB_LightSample tempLightSample = RAB_EmptyLightSample();
            if(RTXDI_CombineDIReservoirs(state, reservoir, 0.5f, reservoir.targetPdf))
            {
                tempLightSample = lightSample;
            }

            for (uint i = 0; i < WORLD_SPACE_RESERVOIR_NUM_PER_GRID; ++i)
            {
                uint wsReservoirIndex = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + i;
                    // clamp(RAB_GetNextRandom(rng) * WORLD_SPACE_RESERVOIR_NUM_PER_GRID, 0, WORLD_SPACE_RESERVOIR_NUM_PER_GRID - 1);
                RTXDI_DIReservoir wsReservoir = RTXDI_UnpackDIReservoir(t_WorldSpaceLightReservoirs[wsReservoirIndex]);
                RAB_LightSample wsLightSample = RAB_SamplePolymorphicLight(
                    RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(wsReservoir), false), 
                    surface, 
                    RTXDI_GetDIReservoirSampleUV(wsReservoir));

                float targetPdf = 0.f;
                if (RTXDI_IsValidDIReservoir(wsReservoir))
                    targetPdf = RAB_GetLightSampleTargetPdfForSurface(wsLightSample, surface);
                if(RTXDI_CombineDIReservoirs(state, wsReservoir, RAB_GetNextRandom(rng), targetPdf))
                {
                    // selectedIndex = wsReservoirIndex;
                    tempLightSample = wsLightSample;
                }
            }
            RTXDI_FinalizeResampling(state, 1.0, state.M);

            reservoir = state;
            lightSample = tempLightSample;
        }
    }

    float3 diffuse = 0;
    float3 specular = 0;
    float lightDistance = 0;
    ShadeSurfaceWithLightSample(reservoir, surface, lightSample, /* previousFrameTLAS = */ false,
        /* enableVisibilityReuse = */ false, diffuse, specular, lightDistance);
    
    // if (any(diffuse > 0) || any(specular > 0))
    {
        if (g_Const.worldSpaceReservoirFlag & WORLD_SPACE_RESERVOIR_UPDATE_PRIMARY)
        {
            CacheEntry gridId;
            if (TryInsertEntry(surface.worldPos, surface.normal, surface.viewDepth, g_Const.sceneGridScale, gridId))
            {
                WSRLightSample wsrLightSample = (WSRLightSample)0;
                wsrLightSample.gridId = gridId;
                wsrLightSample.lightIndex = RTXDI_GetDIReservoirLightIndex(reservoir);
                wsrLightSample.uv = RTXDI_GetDIReservoirSampleUV(reservoir);
                // wsrLightSample.targetPdf = calcLuminance(diffuse * surface.diffuseAlbedo + specular);
                wsrLightSample.targetPdf = RAB_GetLightSampleTargetPdfForSurface(lightSample, surface);
                wsrLightSample.invSourcePdf = RTXDI_GetDIReservoirInvPdf(reservoir);
                wsrLightSample.random = RAB_GetNextRandom(rng);// 0.5f;

                uint sampleCnt;
                InterlockedAdd(u_WorldSpaceGridStatsBuffer[wsrLightSample.gridId].sampleCnt, 1, sampleCnt);
                {
                    uint index;
                    u_WorldSpaceReservoirStats.InterlockedAdd(0, 1, index);
                    u_WorldSpaceLightSamplesBuffer[index] = wsrLightSample;
                }
            }
        }
        
        // specular = DemodulateSpecular(surface.specularF0, specular);

        // StoreShadingOutput(GlobalIndex, pixelPosition,
        //     surface.viewDepth, surface.roughness, diffuse, specular, lightDistance, true, g_Const.restirDI.shadingParams.enableDenoiserInputPacking);
    }
        specular = DemodulateSpecular(surface.specularF0, specular);

        StoreShadingOutput(GlobalIndex, pixelPosition,
            surface.viewDepth, surface.roughness, diffuse, specular, lightDistance, true, g_Const.restirDI.shadingParams.enableDenoiserInputPacking);
}
