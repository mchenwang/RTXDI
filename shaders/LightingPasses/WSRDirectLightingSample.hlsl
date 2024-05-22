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
#include "WSRSampleHelper.hlsli"

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
        0,
        0.001f);

    RAB_LightSample lightSample = RAB_EmptyLightSample();
    RTXDI_DIReservoir reservoir = RTXDI_EmptyDIReservoir();

    // if ((g_Const.worldSpaceReservoirFlag & WORLD_SPACE_RESERVOIR_DI_COMBINE) ||
    //     !(g_Const.worldSpaceReservoirFlag & WORLD_SPACE_RESERVOIR_DI_ENABLE))
    {
        reservoir = RTXDI_SampleLightsForSurface(rng, tileRng, surface,
            sampleParams, g_Const.lightBufferParams, g_Const.restirDI.initialSamplingParams.localLightSamplingMode,
    #if RTXDI_ENABLE_PRESAMPLING
            g_Const.localLightsRISBufferSegmentParams, g_Const.environmentLightRISBufferSegmentParams,
    #if RTXDI_REGIR_MODE != RTXDI_REGIR_MODE_DISABLED
            g_Const.regir,
    #endif
    #endif
            lightSample);
    }
    
    if (g_Const.worldSpaceReservoirFlag & WORLD_SPACE_RESERVOIR_UPDATE_PRIMARY)
    {
        float3 visibility = GetFinalVisibility(SceneBVH, surface, lightSample.position);
        uint gridId = 0;
        if (any(visibility > 0))
        {
            gridId = StoreWorldSpaceLightSample(reservoir, lightSample, rng, surface, g_Const.sceneGridScale);
        }
        u_DebugColor1[pixelPosition] = float4(gridId * 1.f / (128*128*128), 0., 0., 1.);
    }

    if (!(g_Const.worldSpaceReservoirFlag & WORLD_SPACE_RESERVOIR_DI_COMBINE))
        reservoir = RTXDI_EmptyDIReservoir();
        
    if (g_Const.worldSpaceReservoirFlag & WORLD_SPACE_RESERVOIR_DI_ENABLE)
    {
        bool useJitter = g_Const.worldSpaceReservoirFlag & WORLD_SPACE_RESERVOIR_SAMPLE_WITH_JITTER;
        SampleWorldSpaceReservoir(reservoir, lightSample, rng, surface, g_Const.view.cameraDirectionOrPosition.xyz, g_Const.sceneGridScale, useJitter);
    }

    float3 diffuse = 0;
    float3 specular = 0;
    float lightDistance = 0;

    if (RTXDI_IsValidDIReservoir(reservoir))
        ShadeSurfaceWithLightSample(reservoir, surface, lightSample, /* previousFrameTLAS = */ false,
            /* enableVisibilityReuse = */ false, diffuse, specular, lightDistance);

    // if (g_Const.worldSpaceReservoirFlag & WORLD_SPACE_RESERVOIR_UPDATE_PRIMARY)
    // {
    //    uint gridId = StoreWorldSpaceLightSample(reservoir, lightSample, rng, surface, g_Const.sceneGridScale);
    //    u_DebugColor1[pixelPosition] = float4(gridId * 1.f / (128*128*128), 0., 0., 1.);
    // }

    specular = DemodulateSpecular(surface.specularF0, specular);

    StoreShadingOutput(GlobalIndex, pixelPosition,
        surface.viewDepth, surface.roughness, diffuse, specular, lightDistance, true, g_Const.restirDI.shadingParams.enableDenoiserInputPacking);
}
