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

    if (RAB_IsSurfaceValid(surface))
    {
        float3 gridNormal = (g_Const.worldSpaceReservoirFlag & WORLD_SPACE_GRID_USE_GEO_NORMAL) ?
            surface.geoNormal : surface.normal;
        bool useJitter = g_Const.worldSpaceReservoirFlag & WORLD_SPACE_RESERVOIR_SAMPLE_WITH_JITTER;
        uint grid = SampleWorldSpaceReservoir(rng, surface, gridNormal, g_Const.view.cameraDirectionOrPosition.xyz, g_Const.sceneGridScale, 
            useJitter, reservoir, lightSample);

        // uint geoNormalBits =
        //     (surface.geoNormal.x >= 0 ? 1 : 0) +
        //     (surface.geoNormal.y >= 0 ? 2 : 0) +
        //     (surface.geoNormal.z >= 0 ? 4 : 0);
        // uint normalBits =
        //     (surface.normal.x >= 0 ? 1 : 0) +
        //     (surface.normal.y >= 0 ? 2 : 0) +
        //     (surface.normal.z >= 0 ? 4 : 0);
        
        // const float3 colors[8] = {float3(0, 0, 0), float3(1, 0, 0), float3(0, 1, 0), float3(0, 0, 1), 
        //                     float3(1, 0, 1), float3(1, 1, 0), float3(0, 1, 1), float3(1, 1, 1)};

        // if (grid == 40 * 128 * 128 * 128 / 255)
        //     u_DebugColor1[pixelPosition] = float4(0.f, 1.f, 0.f, 1.f);
        // else
            // u_DebugColor1[pixelPosition] = float4(lightSample.radiance, 1.f);
            // u_DebugColor2[pixelPosition] = float4(grid * 1.f / WORLD_GRID_SIZE, 0.f, 0.f, 1.f);
            u_DebugColor2[pixelPosition] = float4(grid * 1.f / WORLD_SPACE_RESERVOIR_NUM_PER_GRID, 0.f, 0.f, 1.f);
    
    }
    
    float3 diffuse = 0;
    float3 specular = 0;
    float lightDistance = 0;

    if (RTXDI_IsValidDIReservoir(reservoir))
        ShadeSurfaceWithLightSample(reservoir, surface, lightSample, /* previousFrameTLAS = */ false,
            /* enableVisibilityReuse = */ false, diffuse, specular, lightDistance);

    specular = DemodulateSpecular(surface.specularF0, specular);

    StoreShadingOutput(GlobalIndex, pixelPosition,
        surface.viewDepth, surface.roughness, diffuse, specular, lightDistance, true, g_Const.restirDI.shadingParams.enableDenoiserInputPacking);
}
