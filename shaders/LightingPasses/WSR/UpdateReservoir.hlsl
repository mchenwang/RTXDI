#include <rtxdi/RtxdiParameters.h>
#include <donut/shaders/brdf.hlsli>
#include <donut/shaders/bindless.h>

#include "../../SceneGeometry.hlsli"
#include "../../HelperFunctions.hlsli"
#include "../../ShaderParameters.h"
#include "Helper.hlsli"
#include "RAB_DIReservoir.hlsl"

StructuredBuffer<WSRLightSample> t_WorldSpaceLightSamplesBuffer : register(t0);
ByteAddressBuffer t_IndirectParamsBuffer : register(t1);
RWStructuredBuffer<WorldSpaceDIReservoir> u_WorldSpaceLightReservoirs : register(u0);
RWStructuredBuffer<WSRGridStats> u_WorldSpaceGridStatsBuffer : register(u1);

Buffer<uint> t_GridQueue : register(t2);
StructuredBuffer<WSRSurfaceData> t_WorldSpaceReservoirSurfaceCandidatesBuffer : register(t3);
StructuredBuffer<PolymorphicLightInfo> t_LightDataBuffer : register(t4);

SamplerState s_EnvironmentSampler : register(s0);

#define IES_SAMPLER s_EnvironmentSampler
#include "../../PolymorphicLight.hlsli"

typedef PolymorphicLightInfo RAB_LightInfo;

RAB_LightInfo RAB_LoadLightInfo(uint index, bool previousFrame)
{
    return t_LightDataBuffer[index];
}

RAB_LightSample RAB_SamplePolymorphicLight(RAB_LightInfo lightInfo, RAB_Surface surface, float2 uv)
{
    PolymorphicLightSample pls = PolymorphicLight::calcSample(lightInfo, uv, surface.worldPos);

    RAB_LightSample lightSample;
    lightSample.position = pls.position;
    lightSample.normal = pls.normal;
    lightSample.radiance = pls.radiance;
    lightSample.solidAnglePdf = pls.solidAnglePdf;
    lightSample.lightType = getLightType(lightInfo);
    return lightSample;
}

// #define RTXDI_ENABLE_STORE_RESERVOIR 0
// #define RTXDI_LIGHT_RESERVOIR_BUFFER u_WorldSpaceLightReservoirs
// #include <rtxdi/DIReservoir.hlsli>

// groupshared RTXDI_DIReservoir reservoir_cache[WORLD_SPACE_RESERVOIR_NUM_PER_GRID];
groupshared uint surface_id_cache[WORLD_SPACE_RESERVOIR_NUM_PER_GRID];

[numthreads(WORLD_SPACE_RESERVOIR_NUM_PER_GRID, 1, 1)]
void main(uint3 GlobalIndex : SV_DispatchThreadID, uint3 Gid : SV_GroupID, uint3 GTid : SV_GroupThreadID)
{
    if (Gid.x >= WORLD_SPACE_UPDATABLE_GRID_PER_FRAME_MAX_NUM) return;

    const uint maxSampleNum = t_IndirectParamsBuffer.Load(28);
    const uint iterateCnt   = t_IndirectParamsBuffer.Load(12);

    uint gridId = t_GridQueue[Gid.x];

    WSRGridStats stats = u_WorldSpaceGridStatsBuffer[gridId];

    RAB_RandomSamplerState rng = RAB_InitRandomSampler(uint2(Gid.x, GTid.x), iterateCnt + 11 * 13);
    uint sampleCnt = stats.sampleCnt;

    uint reservoirIndex = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + GTid.x;

    if (GTid.x == 0)
    {
        for (uint i = 0; i < WORLD_SPACE_RESERVOIR_NUM_PER_GRID; ++i)
        {
            surface_id_cache[i] = clamp(floor(RAB_GetNextRandom(rng) * sampleCnt), 0, sampleCnt - 1) + stats.offset;
        }
    }
    GroupMemoryBarrierWithGroupSync();

    RAB_Surface newSurface = UnpackWSRSurface(t_WorldSpaceLightSamplesBuffer[surface_id_cache[GTid.x]].surface);
    RTXDI_DIReservoir newReservoir = RTXDI_EmptyDIReservoir();

    for (uint i = 0; i < WORLD_SPACE_LIGHT_SAMPLE_NUM_PER_RESERVOIR; ++i)
    {
        uint sampleIndex = clamp(floor(RAB_GetNextRandom(rng) * sampleCnt), 0, sampleCnt - 1) + stats.offset;
        
        WSRLightSample wsLightSample = t_WorldSpaceLightSamplesBuffer[sampleIndex];
        if (wsLightSample.gridId != gridId || wsLightSample.lightIndex == 0) continue;
        
        RAB_LightInfo lightInfo = RAB_LoadLightInfo(wsLightSample.lightIndex, false);

        RAB_LightSample lightSample = RAB_SamplePolymorphicLight(lightInfo, newSurface, wsLightSample.uv);
        
        float targetPdf = RAB_GetLightSampleTargetPdfForSurface(lightSample, newSurface);
        RTXDI_StreamSample(newReservoir, wsLightSample.lightIndex, wsLightSample.uv, RAB_GetNextRandom(rng), targetPdf, wsLightSample.invSourcePdf);
    }
    RTXDI_FinalizeResampling(newReservoir, 1.0, newReservoir.M);
    // newReservoir.M = 1;

    RAB_Surface surface = (RAB_Surface)0;
    RAB_Surface preSurface = UnpackWSRSurface(u_WorldSpaceLightReservoirs[reservoirIndex].packedSurface);

    RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    RTXDI_DIReservoir preReservoir = RTXDI_UnpackDIReservoir(u_WorldSpaceLightReservoirs[reservoirIndex].packedReservoir);

    if (RTXDI_IsValidDIReservoir(newReservoir))
    {
        preReservoir.M = min(preReservoir.M, 20 * newReservoir.M);
        if (preReservoir.age < 30)
        {
            RTXDI_CombineDIReservoirs(state, preReservoir, 0.5f, preReservoir.targetPdf);

            surface = preSurface;

            RAB_LightSample newLightSample = RAB_SamplePolymorphicLight(
                RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(newReservoir), false),
                surface, RTXDI_GetDIReservoirSampleUV(newReservoir));

            float pi = state.targetPdf;
            float piSum = state.targetPdf * preReservoir.M;

            bool selected = false;
            float targetPdf = RAB_GetLightSampleTargetPdfForSurface(newLightSample, surface);
            if(RTXDI_CombineDIReservoirs(state, newReservoir, RAB_GetNextRandom(rng), targetPdf))
            {
                selected = true;
            }

            RAB_LightSample selectedLightSampleAtNeighbor = RAB_SamplePolymorphicLight(
                RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(state), false),
                newSurface, RTXDI_GetDIReservoirSampleUV(state));

            float ps = RAB_GetLightSampleTargetPdfForSurface(selectedLightSampleAtNeighbor, newSurface);
            piSum += ps * newReservoir.M;
            
            if (selected) pi = ps;

            RTXDI_FinalizeResampling(state, pi, piSum);
        }
        else
        {
            RTXDI_CombineDIReservoirs(state, newReservoir, 0.5f, newReservoir.targetPdf);

            surface = newSurface;

            RAB_LightSample preLightSample = RAB_SamplePolymorphicLight(
                RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(preReservoir), false),
                surface, RTXDI_GetDIReservoirSampleUV(preReservoir));

            float pi = state.targetPdf;
            float piSum = state.targetPdf * newReservoir.M;

            bool selected = false;
            float targetPdf = RAB_GetLightSampleTargetPdfForSurface(preLightSample, surface);
            if(RTXDI_CombineDIReservoirs(state, preReservoir, RAB_GetNextRandom(rng), targetPdf))
            {
                selected = true;
            }

            RAB_LightSample selectedLightSampleAtNeighbor = RAB_SamplePolymorphicLight(
                RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(state), false),
                preSurface, RTXDI_GetDIReservoirSampleUV(state));

            float ps = RAB_GetLightSampleTargetPdfForSurface(selectedLightSampleAtNeighbor, preSurface);
            piSum += ps * preReservoir.M;
            
            if (selected) pi = ps;

            RTXDI_FinalizeResampling(state, pi, piSum);
        }
    }
    else
    {
        surface = preSurface;
        state = preReservoir;
    }

    state.age++;

    u_WorldSpaceLightReservoirs[reservoirIndex].packedSurface = PackWSRSurface(newSurface);
    u_WorldSpaceLightReservoirs[reservoirIndex].packedReservoir = RTXDI_PackDIReservoir(state);

    
    // uint reservoirIndex = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + ((GTid.x + iterateCnt) % WORLD_SPACE_RESERVOIR_NUM_PER_GRID);

    // RAB_Surface preSurface = UnpackWSRSurface(u_WorldSpaceLightReservoirs[reservoirIndex].packedSurface);
    // RAB_Surface newSurface = preSurface;

    // RTXDI_DIReservoir preReservoir = RTXDI_UnpackDIReservoir(u_WorldSpaceLightReservoirs[reservoirIndex].packedReservoir);
    // RTXDI_DIReservoir newReservoir = RTXDI_EmptyDIReservoir();

    // if (preReservoir.age > 30) preReservoir = RTXDI_EmptyDIReservoir();

    // if (GTid.x < stats.candidateSurfaceCnt)
    // {
    //     int candidateIndex = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + GTid.x;
    //     newSurface = UnpackWSRSurface(t_WorldSpaceReservoirSurfaceCandidatesBuffer[candidateIndex]);
    // }

    // uint sampleCnt = 0;
    // float rand = 0.f;
    // // uint offset = stats.offset;
    // // for (uint i = 0; i < WORLD_SPACE_LIGHT_SAMPLES_PER_GRID_MAX_NUM; ++i)
    // uint offset = GTid.x * WORLD_SPACE_LIGHT_SAMPLE_NUM_PER_RESERVOIR + stats.offset;
    // for (uint i = 0; i < WORLD_SPACE_LIGHT_SAMPLE_NUM_PER_RESERVOIR; ++i)
    // {
    //     uint index = offset + i;
    //     if (index >= maxSampleNum) break;

    //     WSRLightSample lightSample = t_WorldSpaceLightSamplesBuffer[index];
    //     if (lightSample.gridId != gridId) break;

    //     if (lightSample.lightIndex == 0) continue;

    //     rand += lightSample.random;
        
    //     RAB_LightInfo lightInfo = RAB_LoadLightInfo(lightSample.lightIndex, false);

    //     RAB_LightSample wsLightSample = RAB_SamplePolymorphicLight(lightInfo, newSurface, lightSample.uv);
        
    //     float targetPdf = RAB_GetLightSampleTargetPdfForSurface(wsLightSample, newSurface);
    //     // RTXDI_StreamSample(newReservoir, lightSample.lightIndex, lightSample.uv, lightSample.random, targetPdf, lightSample.invSourcePdf);
    //     sampleCnt++;

    //     RTXDI_StreamSample(newReservoir, lightSample.lightIndex, lightSample.uv, lightSample.random, lightSample.targetPdf, lightSample.invSourcePdf);
    // }
    // rand /= sampleCnt;
    
    // RTXDI_FinalizeResampling(newReservoir, 1.0, newReservoir.M);
    // newReservoir.M = 1;

    // RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    // RTXDI_CombineDIReservoirs(state, newReservoir, 0.5f, newReservoir.targetPdf);
    
    //     uint maxReuseNum = state.M * 20;
    //     preReservoir.M = min(preReservoir.M, maxReuseNum);
        
    //     float targetPdf = 0.f;
    //     if (RTXDI_IsValidDIReservoir(preReservoir))
    //         targetPdf = preReservoir.targetPdf;
        
    //     if (RTXDI_CombineDIReservoirs(state, preReservoir, 1.0 - rand, targetPdf))
    //         state.age++;

    // RTXDI_FinalizeResampling(state, 1.0, state.M);
    // state.M = 1;
    // u_WorldSpaceLightReservoirs[reservoirIndex].packedSurface = PackWSRSurface(newSurface);
    // u_WorldSpaceLightReservoirs[reservoirIndex].packedReservoir = RTXDI_PackDIReservoir(state);

    ////

    // RTXDI_DIReservoir newReservoir = RTXDI_EmptyDIReservoir();

    // uint offset = GTid.x * WORLD_SPACE_LIGHT_SAMPLE_NUM_PER_RESERVOIR + stats.offset;

    // float rand = 0.f;
    // for (uint i = 0; i < WORLD_SPACE_LIGHT_SAMPLE_NUM_PER_RESERVOIR; ++i)
    // {
    //     uint index = offset + i;
    //     if (index >= maxSampleNum) break;

    //     WSRLightSample lightSample = t_WorldSpaceLightSamplesBuffer[index];
    //     if (lightSample.gridId != gridId) break;

    //     if (lightSample.lightIndex == 0) continue;

    //     rand += lightSample.random;
    //     RTXDI_StreamSample(newReservoir, lightSample.lightIndex, lightSample.uv, lightSample.random, lightSample.targetPdf, lightSample.invSourcePdf);
    //     // RTXDI_StreamSample(newReservoir, lightSample.lightIndex, lightSample.uv, lightSample.random, 1, lightSample.invSourcePdf);
    // }
    // rand /= newReservoir.M;
    // RTXDI_FinalizeResampling(newReservoir, 1.0, newReservoir.M);
    // // newReservoir.M = 1;

    // RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();

    // // if (RTXDI_IsValidDIReservoir(newReservoir))
    //     RTXDI_CombineDIReservoirs(state, newReservoir, 0.5f, newReservoir.targetPdf);

    // // uint reservoirIndex = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + ((GTid.x + iterateCnt) % WORLD_SPACE_RESERVOIR_NUM_PER_GRID);
    // // uint reservoirIndex = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + GTid.x;
    // RTXDI_DIReservoir preReservoir = RTXDI_UnpackDIReservoir(u_WorldSpaceLightReservoirs[reservoirIndex].packedReservoir);

    // // if (RTXDI_IsValidDIReservoir(preReservoir))
    // {
    //     // if (preReservoir.age > 30)
    //     // {
    //     //     preReservoir = RTXDI_EmptyDIReservoir();
    //     // }

    //     uint maxReuseNum = state.M * 20;
    //     preReservoir.M = min(preReservoir.M, maxReuseNum);
        
    //     float targetPdf = 0.f;
    //     if (RTXDI_IsValidDIReservoir(preReservoir))
    //         targetPdf = preReservoir.targetPdf;
    //         // targetPdf = 1.f;
        
    //     if (RTXDI_CombineDIReservoirs(state, preReservoir, 1.0 - rand, targetPdf))
    //         state.age++;
    // }
    
    // RTXDI_FinalizeResampling(state, 1.0, state.M);
    
    // u_WorldSpaceLightReservoirs[reservoirIndex].packedSurface = PackWSRSurface(newSurface);
    // u_WorldSpaceLightReservoirs[reservoirIndex].packedReservoir = RTXDI_PackDIReservoir(state);
    

    // reservoir_cache[GTid.x] = state;
    // GroupMemoryBarrierWithGroupSync();

    // if (GTid.x == 0)
    // {
    //     state = RTXDI_EmptyDIReservoir();
    //     for (uint x = 0; x < WORLD_SPACE_RESERVOIR_NUM_PER_GRID; ++x)
    //     {
    //         if (RTXDI_IsValidDIReservoir(reservoir_cache[x]))
    //         {
    //             RTXDI_CombineDIReservoirs(state, reservoir_cache[x], 0.5f, reservoir_cache[x].targetPdf);
    //         }
    //     }
    //     RTXDI_FinalizeResampling(state, 1.0, state.M);
    //     state.age++;

    //     for (uint y = 0; y < WORLD_SPACE_RESERVOIR_NUM_PER_GRID; ++y)
    //     {
    //         if (RTXDI_IsValidDIReservoir(reservoir_cache[y]))
    //         {
    //             u_WorldSpaceLightReservoirs[gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + y] = RTXDI_PackDIReservoir(reservoir_cache[y]);
    //         }
    //         else
    //         {
    //             u_WorldSpaceLightReservoirs[gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + y] = RTXDI_PackDIReservoir(state);
    //         }
    //     }
    // }
}