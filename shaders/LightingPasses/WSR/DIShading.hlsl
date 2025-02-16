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

#include "../RtxdiApplicationBridge.hlsli"

#include <rtxdi/DIResamplingFunctions.hlsli>

#ifdef WITH_NRD
#define NRD_HEADER_ONLY
#include <NRD.hlsli>
#endif

#include "../ShadingHelpers.hlsli"
#include "Helper.hlsli"

#if USE_RAY_QUERY
[numthreads(RTXDI_SCREEN_SPACE_GROUP_SIZE, RTXDI_SCREEN_SPACE_GROUP_SIZE, 1)]
void main(uint2 GlobalIndex : SV_DispatchThreadID, uint2 LocalIndex : SV_GroupThreadID, uint2 GroupIdx : SV_GroupID)
#else
[shader("raygeneration")]
void RayGen()
#endif
{
#if !USE_RAY_QUERY
    uint2 GlobalIndex = DispatchRaysIndex().xy;
#endif

    const RTXDI_RuntimeParameters params = g_Const.runtimeParams;

    uint2 pixelPosition = RTXDI_ReservoirPosToPixelPos(GlobalIndex, params.activeCheckerboardField);

    RAB_Surface surface = RAB_GetGBufferSurface(pixelPosition, false);

    RAB_RandomSamplerState rng = RAB_InitRandomSampler(GlobalIndex, 5);

    RAB_LightSample lightSample = RAB_EmptyLightSample();
    RTXDI_DIReservoir reservoir = RTXDI_EmptyDIReservoir();

    u_DebugColor2[pixelPosition] = float4(0.f, 0.f, 0.f, 1.f);

    if (g_Const.worldSpaceReservoirFlag & WORLD_SPACE_RESERVOIR_SOURCE_COMBINE)
    {
        RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
        RTXDI_DIReservoir sourceReservoir = RTXDI_LoadDIReservoir(g_Const.restirDI.reservoirBufferParams, GlobalIndex, g_Const.restirDI.bufferIndices.shadingInputBufferIndex);
        RAB_LightSample selectedLightSample = RAB_EmptyLightSample();
        RTXDI_CombineDIReservoirs(state, sourceReservoir, 0.5f, sourceReservoir.targetPdf);

        if (RTXDI_IsValidDIReservoir(sourceReservoir))
        {
            selectedLightSample = RAB_SamplePolymorphicLight(
                RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(sourceReservoir), false), 
                surface, RTXDI_GetDIReservoirSampleUV(sourceReservoir));
        }
        
        RTXDI_DIReservoir gridReservoir = RTXDI_EmptyDIReservoir();
        RAB_LightSample gridLightSample = RAB_EmptyLightSample();
        bool useJitter = g_Const.worldSpaceReservoirFlag & WORLD_SPACE_RESERVOIR_SAMPLE_WITH_JITTER;
        SampleWorldSpaceReservoir(rng, surface, g_Const.view.cameraDirectionOrPosition.xyz, g_Const.sceneGridScale, 
            useJitter, gridReservoir, gridLightSample);

        float risWeight = 0;
        if (RTXDI_IsValidDIReservoir(gridReservoir))
        {
            risWeight = RAB_GetLightSampleTargetPdfForSurface(gridLightSample, surface);
            
            float denominator = gridReservoir.targetPdf * gridReservoir.M;
            gridReservoir.weightSum *= denominator;
            denominator = risWeight * gridReservoir.M;
            gridReservoir.weightSum = (denominator == 0.0) ? 0.0 : gridReservoir.weightSum / denominator;
        }
        
        if (RTXDI_CombineDIReservoirs(state, gridReservoir, RAB_GetNextRandom(rng), risWeight))
        {
            selectedLightSample = gridLightSample;

            u_DebugColor2[pixelPosition] = float4(0.f, 0.f, 1.f, 1.f);
        }
        
        RTXDI_FinalizeResampling(state, 1, state.M);

        reservoir = state;
        lightSample = selectedLightSample;
    }
    else
    {
        bool useJitter = g_Const.worldSpaceReservoirFlag & WORLD_SPACE_RESERVOIR_SAMPLE_WITH_JITTER;
        uint grid = SampleWorldSpaceReservoir(rng, surface, g_Const.view.cameraDirectionOrPosition.xyz, g_Const.sceneGridScale, 
            useJitter, reservoir, lightSample);
    }

    float3 diffuse = 0;
    float3 specular = 0;
    float lightDistance = 0;

    if (RTXDI_IsValidDIReservoir(reservoir))
        ShadeSurfaceWithLightSample(reservoir, surface, lightSample, /* previousFrameTLAS = */ false,
            /* enableVisibilityReuse = */ true, diffuse, specular, lightDistance);

    specular = DemodulateSpecular(surface.specularF0, specular);

    StoreShadingOutput(GlobalIndex, pixelPosition,
        surface.viewDepth, surface.roughness, diffuse, specular, lightDistance, true, g_Const.restirDI.shadingParams.enableDenoiserInputPacking);
}
