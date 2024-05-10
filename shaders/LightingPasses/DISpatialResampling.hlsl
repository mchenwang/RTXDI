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

    const RTXDI_RuntimeParameters params = g_Const.runtimeParams;

    uint2 pixelPosition = RTXDI_ReservoirPosToPixelPos(GlobalIndex, params.activeCheckerboardField);

    RAB_RandomSamplerState rng = RAB_InitRandomSampler(pixelPosition, 3);

    RAB_Surface surface = RAB_GetGBufferSurface(pixelPosition, false);

    RTXDI_DIReservoir spatialResult = RTXDI_EmptyDIReservoir();
    
    if (RAB_IsSurfaceValid(surface))
    {
        RTXDI_DIReservoir centerSample = RTXDI_LoadDIReservoir(g_Const.restirDI.reservoirBufferParams,
            GlobalIndex, g_Const.restirDI.bufferIndices.spatialResamplingInputBufferIndex);

        RAB_LightSample lightSample = (RAB_LightSample)0;
            
        // if (g_Const.worldSpaceReservoirFlag & WORLD_SPACE_RESERVOIR_DI_ENABLE)
        // {
        //     float3 posJitter = float3(0.f, 0.f, 0.f);

        //     float3 tangent, bitangent;
        //     branchlessONB(surface.normal, tangent, bitangent);
        //     // RAB_RandomSamplerState rng = RAB_InitRandomSampler(GlobalIndex, 5);
        //     float2 t = float2(RAB_GetNextRandom(rng), RAB_GetNextRandom(rng)) * 2.f - 1.f;
        //     posJitter = tangent * t.x + bitangent * t.y;
        //     posJitter *= g_Const.sceneGridScale;
        //     CacheEntry gridId;
        //     if (FindEntry(surface.worldPos + posJitter, surface.normal, surface.viewDepth, g_Const.sceneGridScale, gridId))
        //     {
        //         RTXDI_DIReservoir wsReservoir = RTXDI_UnpackDIReservoir(t_WorldSpaceLightReservoirs[gridId]);

        //         if (RTXDI_IsValidDIReservoir(wsReservoir))
        //         {
        //             if(RTXDI_CombineDIReservoirs(centerSample, wsReservoir, 0.5f, wsReservoir.targetPdf))
        //             {
        //                 lightSample = RAB_SamplePolymorphicLight(
        //                     RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(wsReservoir), false), 
        //                     surface, 
        //                     RTXDI_GetDIReservoirSampleUV(wsReservoir));
        //             }
        //             RTXDI_FinalizeResampling(centerSample, 1.0, centerSample.M);
        //         }
        //     }
        // }

        RTXDI_DISpatialResamplingParameters sparams;
        sparams.sourceBufferIndex = g_Const.restirDI.bufferIndices.spatialResamplingInputBufferIndex;
        sparams.numSamples = g_Const.restirDI.spatialResamplingParams.numSpatialSamples;
        sparams.numDisocclusionBoostSamples = g_Const.restirDI.spatialResamplingParams.numDisocclusionBoostSamples;
        sparams.targetHistoryLength = g_Const.restirDI.temporalResamplingParams.maxHistoryLength;
        sparams.biasCorrectionMode = g_Const.restirDI.spatialResamplingParams.spatialBiasCorrection;
        sparams.samplingRadius = g_Const.restirDI.spatialResamplingParams.spatialSamplingRadius;
        sparams.depthThreshold = g_Const.restirDI.spatialResamplingParams.spatialDepthThreshold;
        sparams.normalThreshold = g_Const.restirDI.spatialResamplingParams.spatialNormalThreshold;
        sparams.enableMaterialSimilarityTest = true;
        sparams.discountNaiveSamples = g_Const.restirDI.spatialResamplingParams.discountNaiveSamples;

        spatialResult = RTXDI_DISpatialResampling(pixelPosition, surface, centerSample, 
             rng, params, g_Const.restirDI.reservoirBufferParams, sparams, lightSample);
    }

    RTXDI_StoreDIReservoir(spatialResult, g_Const.restirDI.reservoirBufferParams, GlobalIndex, g_Const.restirDI.bufferIndices.spatialResamplingOutputBufferIndex);
}