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

#include <rtxdi/DIResamplingFunctions.hlsli>
#if RTXDI_REGIR_MODE != RTXDI_REGIR_DISABLED
#include "rtxdi/ReGIRSampling.hlsli"
#endif

#ifdef WITH_NRD
#define NRD_HEADER_ONLY
#include <NRD.hlsli>
#endif

#include "ShadingHelpers.hlsli"
#include "WSRSampleHelper.hlsli"

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

    RTXDI_DIReservoir reservoir = RTXDI_LoadDIReservoir(g_Const.restirDI.reservoirBufferParams, GlobalIndex, g_Const.restirDI.bufferIndices.shadingInputBufferIndex);

    RAB_RandomSamplerState rng = RAB_InitRandomSampler(GlobalIndex, 5);

    float3 diffuse = 0;
    float3 specular = 0;
    float lightDistance = 0;
    float2 currLuminance = 0;

    if (RTXDI_IsValidDIReservoir(reservoir))
    {
        RAB_LightInfo lightInfo = RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(reservoir), false);

        RAB_LightSample lightSample = RAB_SamplePolymorphicLight(lightInfo,
            surface, RTXDI_GetDIReservoirSampleUV(reservoir));

        
        // if (g_Const.worldSpaceReservoirFlag & WORLD_SPACE_RESERVOIR_DI_ENABLE)
        // {
        //     float3 posJitter = float3(0.f, 0.f, 0.f);

        //     float3 tangent, bitangent;
        //     branchlessONB(surface.normal, tangent, bitangent);
        //     RAB_RandomSamplerState rng = RAB_InitRandomSampler(GlobalIndex, 5);
        //     float2 t = float2(RAB_GetNextRandom(rng), RAB_GetNextRandom(rng)) * 2.f - 1.f;
        //     posJitter = tangent * t.x + bitangent * t.y;
        //     posJitter *= g_Const.sceneGridScale;
        //     CacheEntry gridId;
        //     if (FindEntry(surface.worldPos + posJitter, surface.normal, surface.viewDepth, g_Const.sceneGridScale, gridId))
        //     {
        //         RTXDI_DIReservoir wsReservoir = RTXDI_UnpackDIReservoir(t_WorldSpaceLightReservoirs[gridId]);

        //         if (RTXDI_IsValidDIReservoir(wsReservoir))
        //         {
        //             RAB_LightSample wsLightSample = RAB_SamplePolymorphicLight(
        //                 RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(wsReservoir), false), 
        //                 surface, 
        //                 RTXDI_GetDIReservoirSampleUV(wsReservoir));

        //             if (RTXDI_StreamSample(reservoir, 
        //                 RTXDI_GetDIReservoirLightIndex(wsReservoir),
        //                 RTXDI_GetDIReservoirSampleUV(wsReservoir),
        //                 0.f,
        //                 RAB_GetLightSampleTargetPdfForSurface(wsLightSample, surface),
        //                 RTXDI_GetDIReservoirInvPdf(wsReservoir)))
        //             {
        //                 lightSample = wsLightSample;
        //             }
        //         }
        //     }
        // }

        if (g_Const.worldSpaceReservoirFlag & WORLD_SPACE_RESERVOIR_UPDATE_PRIMARY)
        {
            StoreWorldSpaceLightSample(reservoir, lightSample, rng, surface, g_Const.sceneGridScale);
        }

        bool needToStore = ShadeSurfaceWithLightSample(reservoir, surface, lightSample,
            /* previousFrameTLAS = */ false, /* enableVisibilityReuse = */ true, diffuse, specular, lightDistance);
    
        currLuminance = float2(calcLuminance(diffuse * surface.diffuseAlbedo), calcLuminance(specular));
    
        specular = DemodulateSpecular(surface.specularF0, specular);

        if (needToStore)
        {
            RTXDI_StoreDIReservoir(reservoir, g_Const.restirDI.reservoirBufferParams, GlobalIndex, g_Const.restirDI.bufferIndices.shadingInputBufferIndex);
        }
    }

    // Store the sampled lighting luminance for the gradient pass.
    // Discard the pixels where the visibility was reused, as gradients need actual visibility.
    u_RestirLuminance[GlobalIndex] = currLuminance * (reservoir.age > 0 ? 0 : 1);
    
#if RTXDI_REGIR_MODE != RTXDI_REGIR_DISABLED
    if (g_Const.visualizeRegirCells)
    {
        diffuse *= RTXDI_VisualizeReGIRCells(g_Const.regir, RAB_GetSurfaceWorldPos(surface));
    }
#endif

    StoreShadingOutput(GlobalIndex, pixelPosition, 
        surface.viewDepth, surface.roughness, diffuse, specular, lightDistance, true, g_Const.restirDI.shadingParams.enableDenoiserInputPacking);
}
