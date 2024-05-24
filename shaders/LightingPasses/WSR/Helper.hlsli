#ifndef WSR_SAMPLE_HELPERS_HLSLI
#define WSR_SAMPLE_HELPERS_HLSLI

#include <donut/shaders/utils.hlsli>
#include <donut/shaders/packing.hlsli>
#include "../../HelperFunctions.hlsli"
#include "../HashGridHelper.hlsli"

RAB_RandomSamplerState WSR_InitRandomSampler(uint2 index, uint frameIndex)
{
    return initRandomSampler(index, frameIndex);
}

WSRSurfaceData PackWSRSurface(RAB_Surface surface)
{
    WSRSurfaceData packedSurface = (WSRSurfaceData)0;
    packedSurface.worldPos = surface.worldPos;
    packedSurface.normal = ndirToOctUnorm32(surface.normal);
    packedSurface.diffuseAlbedo = Pack_R11G11B10_UFLOAT(surface.diffuseAlbedo);
    packedSurface.specularAndRoughness = Pack_R8G8B8A8_Gamma_UFLOAT(float4(surface.specularF0, surface.roughness));
    packedSurface.viewDir = ndirToOctUnorm32(surface.viewDir);
    packedSurface.geoNormal = ndirToOctUnorm32(surface.geoNormal);

    return packedSurface;
}

RAB_Surface UnpackWSRSurface(WSRSurfaceData packedSurface)
{
    RAB_Surface surface = (RAB_Surface)0;
    surface.worldPos = packedSurface.worldPos;
    surface.viewDepth = 1.0; // doesn't matter
    surface.normal = octToNdirUnorm32(packedSurface.normal);
    surface.geoNormal = octToNdirUnorm32(packedSurface.geoNormal);
    surface.diffuseAlbedo = Unpack_R11G11B10_UFLOAT(packedSurface.diffuseAlbedo);
    float4 specularRough = Unpack_R8G8B8A8_Gamma_UFLOAT(packedSurface.specularAndRoughness);
    surface.specularF0 = specularRough.rgb;
    surface.roughness = specularRough.a;
    // surface.diffuseProbability = getSurfaceDiffuseProbability(surface);
    surface.viewDir = octToNdirUnorm32(packedSurface.viewDir);

    return surface;
}

uint StoreWorldSpaceLightSample(
    RTXDI_DIReservoir reservoir,
    RAB_LightSample lightSample,
    inout RAB_RandomSamplerState rng,
    RAB_Surface surface,
    float sceneGridScale,
    float visibility = 1.f)
{
    float3 tangent, bitangent;
    branchlessONB(surface.geoNormal, tangent, bitangent);
    float2 t = float2(RAB_GetNextRandom(rng), RAB_GetNextRandom(rng)) * 2.f - 1.f;
    float3 posJitter = tangent * t.x + bitangent * t.y;
    posJitter *= sceneGridScale;

    CacheEntry gridId;
    if (TryInsertEntry(surface.worldPos + posJitter, surface.normal, surface.viewDepth, sceneGridScale, gridId))
    {
        uint index;
        u_WorldSpaceReservoirStats.InterlockedAdd(0, 1, index);
        if (index < WORLD_SPACE_LIGHT_SAMPLES_MAX_NUM)
        {
            WSRLightSample wsrLightSample = (WSRLightSample)0;
            wsrLightSample.gridId = gridId;
            wsrLightSample.lightIndex = RTXDI_GetDIReservoirLightIndex(reservoir);
            wsrLightSample.uv = RTXDI_GetDIReservoirSampleUV(reservoir);
            wsrLightSample.targetPdf = RAB_GetLightSampleTargetPdfForSurface(lightSample, surface) * visibility;
            wsrLightSample.invSourcePdf = RTXDI_GetDIReservoirInvPdf(reservoir);
            wsrLightSample.random = RAB_GetNextRandom(rng);

            wsrLightSample.surface = PackWSRSurface(surface);

            u_WorldSpaceLightSamplesBuffer[index] = wsrLightSample;

            uint sampleCnt;
            InterlockedAdd(u_WorldSpaceGridStatsBuffer[wsrLightSample.gridId].sampleCnt, 1, sampleCnt);

            return gridId;
        }
    }
    return 0;
}


uint SampleWorldSpaceReservoir(
    inout RAB_RandomSamplerState rng,
    RAB_Surface surface,
    float3 viewPos,
    float sceneGridScale,
    bool useJitter,
    out RTXDI_DIReservoir o_reservoir,
    out RAB_LightSample o_lightSample
)
{
    float3 posJitter = float3(0.f, 0.f, 0.f);
    float3 normal = surface.normal;
    
    RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    RAB_LightInfo selectedLight = RAB_EmptyLightInfo();
    RAB_LightSample selectedLightSample = RAB_EmptyLightSample();

    CacheEntry gridId;
    {
        // const int dx[8] = {1, 1, 0, -1, -1, -1,  0,  1};
        // const int dy[8] = {0, 1, 1,  1,  0, -1, -1, -1};
        // for (uint t = 0; t < 3; t++)
        {
            if (useJitter)
            {
                float3 tangent, bitangent;
                branchlessONB(surface.geoNormal, tangent, bitangent);
                float2 t = float2(RAB_GetNextRandom(rng), RAB_GetNextRandom(rng)) * 2.f - 1.f;
                posJitter = tangent * t.x + bitangent * t.y;
                posJitter *= sceneGridScale;
            }
            
            if (FindEntry(surface.worldPos + posJitter, normal, surface.viewDepth, sceneGridScale, gridId))
            {
                for (uint j = 0; j < 5; j++)
                {
                    uint i = clamp(RAB_GetNextRandom(rng) * WORLD_SPACE_RESERVOIR_NUM_PER_GRID, 0, WORLD_SPACE_RESERVOIR_NUM_PER_GRID - 1);
                    uint wsReservoirIndex = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + i;
                    
                    RAB_Surface neighborSurface = UnpackWSRSurface(u_WorldSpaceLightReservoirs[wsReservoirIndex].packedSurface);
                    RTXDI_DIReservoir neighborReservoir = RTXDI_UnpackDIReservoir(u_WorldSpaceLightReservoirs[wsReservoirIndex].packedReservoir);

                    float neighborWeight = 0;
                    RAB_LightInfo candidateLight = RAB_EmptyLightInfo();
                    RAB_LightSample candidateLightSample = RAB_EmptyLightSample();
                    if (RTXDI_IsValidDIReservoir(neighborReservoir))
                    {   
                        candidateLight = RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(neighborReservoir), false);
                        
                        candidateLightSample = RAB_SamplePolymorphicLight(
                            candidateLight, surface, RTXDI_GetDIReservoirSampleUV(neighborReservoir));
                        
                        neighborWeight = RAB_GetLightSampleTargetPdfForSurface(candidateLightSample, surface);
                    }
                    
                    if (RTXDI_CombineDIReservoirs(state, neighborReservoir, RAB_GetNextRandom(rng), neighborWeight))
                    {
                        selectedLight = candidateLight;
                        selectedLightSample = candidateLightSample;
                    }
                }
            }
        }
    }

    RTXDI_FinalizeResampling(state, 1.0, state.M);

    o_reservoir = state;
    o_lightSample = selectedLightSample;
    return gridId;
}

uint XXSampleWorldSpaceReservoir(
    inout RAB_RandomSamplerState rng,
    RAB_Surface surface,
    float3 viewPos,
    float sceneGridScale,
    bool useJitter,
    inout RTXDI_DIReservoir reservoir,
    inout RAB_LightSample lightSample
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
        RAB_LightInfo selectedLight = RAB_EmptyLightInfo();
        RAB_LightSample selectedLightSample = RAB_EmptyLightSample();

        if (RTXDI_CombineDIReservoirs(state, reservoir, 0.5f, reservoir.targetPdf))
        {
            selectedLight = RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(reservoir), false);
            selectedLightSample = lightSample;
        }

        int selectedIndex = -1;
        uint cachedResult = 0;
#if WORLD_SPACE_RESERVOIR_NUM_PER_GRID > 32
        uint cachedResult2 = 0;
#endif
        // for (uint i = 0; i < WORLD_SPACE_RESERVOIR_NUM_PER_GRID; ++i)
        for (uint j = 0; j < 5; ++j)
        {
            uint i = clamp(RAB_GetNextRandom(rng) * WORLD_SPACE_RESERVOIR_NUM_PER_GRID, 0, WORLD_SPACE_RESERVOIR_NUM_PER_GRID - 1);
            uint wsReservoirIndex = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + i;
            
            RAB_Surface neighborSurface = UnpackWSRSurface(u_WorldSpaceLightReservoirs[wsReservoirIndex].packedSurface);
            RTXDI_DIReservoir wsReservoir = RTXDI_UnpackDIReservoir(u_WorldSpaceLightReservoirs[wsReservoirIndex].packedReservoir);

            if (!RTXDI_IsValidDIReservoir(wsReservoir)) continue;
            
            // if ((dot(neighborSurface.normal, surface.normal) < 0.5f) || 
            //      length(neighborSurface.worldPos - surface.worldPos) > 0.5f)
            //     continue;

            if (i < 32) cachedResult |= (1u << i);
#if WORLD_SPACE_RESERVOIR_NUM_PER_GRID > 32
            else if (i < 64) cachedResult2 |= (1u << (i - 32));
#endif
            
            float neighborWeight = 0;
            RAB_LightInfo candidateLight = RAB_EmptyLightInfo();
            RAB_LightSample candidateLightSample = RAB_EmptyLightSample();
            if (RTXDI_IsValidDIReservoir(wsReservoir))
            {   
                candidateLight = RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(wsReservoir), false);
                
                candidateLightSample = RAB_SamplePolymorphicLight(
                    candidateLight, surface, RTXDI_GetDIReservoirSampleUV(wsReservoir));
                
                neighborWeight = RAB_GetLightSampleTargetPdfForSurface(candidateLightSample, surface);
            }
            
            if (RTXDI_CombineDIReservoirs(state, wsReservoir, RAB_GetNextRandom(rng), neighborWeight))
            {
                selectedIndex = int(i);
                selectedLight = candidateLight;
                selectedLightSample = candidateLightSample;
            }
        }

        if (RTXDI_IsValidDIReservoir(state))
        {
            float pi = state.targetPdf;
            float piSum = state.targetPdf * reservoir.M;

            for (uint i = 0; i < WORLD_SPACE_RESERVOIR_NUM_PER_GRID; ++i)
            {
                if (i < 32)
                {
                    if ((cachedResult & (1u << i)) == 0)
                        continue;
                }
#if WORLD_SPACE_RESERVOIR_NUM_PER_GRID > 32
                else if (i < 64)
                {
                    if ((cachedResult2 & (1u << (i - 32))) == 0)
                        continue;
                }
#endif
                uint wsReservoirIndex = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + i;
                RAB_Surface neighborSurface = UnpackWSRSurface(u_WorldSpaceLightReservoirs[wsReservoirIndex].packedSurface);
                RTXDI_DIReservoir wsReservoir = RTXDI_UnpackDIReservoir(u_WorldSpaceLightReservoirs[wsReservoirIndex].packedReservoir);

                const RAB_LightSample selectedSampleAtNeighbor = RAB_SamplePolymorphicLight(
                    selectedLight, neighborSurface, RTXDI_GetDIReservoirSampleUV(state));

                float ps = RAB_GetLightSampleTargetPdfForSurface(selectedSampleAtNeighbor, neighborSurface);

                pi = selectedIndex == i ? ps : pi;
                piSum += ps * wsReservoir.M;
            }
            RTXDI_FinalizeResampling(state, pi, piSum);
            reservoir = state;
            lightSample = selectedLightSample;

            // RTXDI_FinalizeResampling(state, 1, state.M);
            // reservoir = state;
            // lightSample = selectedLightSample;
        }
    }

    return gridId;
}

#endif