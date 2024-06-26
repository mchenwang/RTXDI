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

uint GetSubCellIndex(float3 surfaceNormal)
{
    return (surfaceNormal.x >= 0 ? 1 : 0) +
           (surfaceNormal.y >= 0 ? 2 : 0) +
           (surfaceNormal.z >= 0 ? 4 : 0);
}

WSRSurfaceData PackWSRSurface(RAB_Surface surface)
{
    WSRSurfaceData packedSurface = (WSRSurfaceData)0;
    packedSurface.worldPos = surface.worldPos;
    packedSurface.diffuseProbability = surface.diffuseProbability;
    packedSurface.normal = ndirToOctUnorm32(surface.normal);
    packedSurface.diffuseAlbedo = Pack_R11G11B10_UFLOAT(surface.diffuseAlbedo);
    packedSurface.specularAndRoughness = Pack_R8G8B8A8_Gamma_UFLOAT(float4(surface.specularF0, surface.roughness));
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
    surface.diffuseProbability = packedSurface.diffuseProbability;
    // surface.viewDir = octToNdirUnorm32(packedSurface.viewDir);

    return surface;
}

float WSR_GetLightSampleTargetDistributionForGrid(RAB_LightSample lightSample, RAB_Surface aggregateSurface, float r, float thetaN)
{
    return RAB_GetLightSampleTargetPdfForSurface(lightSample, aggregateSurface);
    // if (lightSample.solidAnglePdf <= 0)
    //     return 0;

    // float lightDistance = distance(aggregateSurface.worldPos, lightSample.position);
    // float thetaD = asin(r / lightDistance);
    // float averageSquaredDistance = 0.6f * r * r + lightDistance * lightDistance;

    // // float3 psi = normalize(lightSample.position - aggregateSurface.worldPos);
    // float3 psi = (lightSample.position - aggregateSurface.worldPos);

    // float G = 1.f
    //         * cos(max(acos(dot(aggregateSurface.normal, psi)) - thetaN - thetaD, 0.f)) 
    //         * cos(max(acos(dot(lightSample.normal, psi)) - thetaD, 0.f))
    //         // * (1.f / averageSquaredDistance)
    //         * (1.f / lightSample.solidAnglePdf)
    //         ;

    // float3 L = (lightSample.position - aggregateSurface.worldPos) / lightDistance;

    // float3 V = aggregateSurface.viewDir;
    // float3 diffuse = Lambert(aggregateSurface.normal, -L) * aggregateSurface.diffuseAlbedo;
    // float3 specular = GGX_times_NdotL(V, L, aggregateSurface.normal, max(aggregateSurface.roughness, kMinRoughness), aggregateSurface.specularF0);

    // float3 scattering = lerp(specular, diffuse, aggregateSurface.diffuseProbability);

    // return calcLuminance(lightSample.radiance * G * scattering);
}

uint StoreWorldSpaceLightSample(
    RTXDI_DIReservoir reservoir,
    RAB_LightSample lightSample,
    uint2 pixelPosition,
    RAB_Surface surface,
    float sceneGridScale,
    float3 gridNormal,
    float visibility = 1.f)
{
    GridEntry entry;
    if (!InsertGridEntry(surface.worldPos, gridNormal, surface.viewDepth, sceneGridScale, entry))
        return 0;
    
    uint index;
    u_WorldSpaceReservoirStats.InterlockedAdd(0, 1, index);
    // if (index < WORLD_SPACE_LIGHT_SAMPLES_MAX_NUM)
    {
        WSRLightSample wsrLightSample = (WSRLightSample)0;
        wsrLightSample.gridIdOffset = (entry.gridId << WORLD_GRID_SUB_CELL_OFFSET_BIT_NUM) | (entry.subCellIndex & WORLD_GRID_SUB_CELL_OFFSET_BIT_MASK);
        wsrLightSample.lightIndex = RTXDI_GetDIReservoirLightIndex(reservoir);
        wsrLightSample.uv = RTXDI_GetDIReservoirSampleUV(reservoir);
        wsrLightSample.invSourcePdf = RTXDI_GetDIReservoirInvPdf(reservoir);
        wsrLightSample.packedPixelPosition = (pixelPosition.y << 16) | (pixelPosition.x & 0xffff);

        wsrLightSample.packedReservoir = RTXDI_PackDIReservoir(reservoir);

        u_WorldSpaceLightSamplesBuffer[index] = wsrLightSample;

        uint sampleCnt;
        InterlockedAdd(u_WorldSpaceGridStatsBuffer[entry.gridId].sampleCnt, 1, sampleCnt);

        u_WorldSpaceGridStatsBuffer[entry.gridId].gridLevel = entry.gridLevel;

        return entry.gridId;
    }

    return 0;
}


uint SampleWorldSpaceReservoir(
    inout RAB_RandomSamplerState rng,
    RAB_Surface surface,
    float3 gridNormal,
    float3 viewPos,
    float sceneGridScale,
    bool useJitter,
    out RTXDI_DIReservoir o_reservoir,
    out RAB_LightSample o_lightSample
)
{
    float3 posJitter = float3(0.f, 0.f, 0.f);
    
    RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    RAB_LightInfo selectedLight = RAB_EmptyLightInfo();
    RAB_LightSample selectedLightSample = RAB_EmptyLightSample();

    GridEntry entry = (GridEntry)0;
    {
        {
            if (useJitter)
            {
                float3 tangent, bitangent;
                branchlessONB(gridNormal, tangent, bitangent);
                float2 t = float2(RAB_GetNextRandom(rng), RAB_GetNextRandom(rng)) * 2.f - 1.f;
                posJitter = tangent * t.x + bitangent * t.y;
                posJitter *= GetVoxelSize(GetGridLevel(surface.viewDepth), sceneGridScale);
            }

            bool valid = FindGridEntry(surface.worldPos + posJitter, gridNormal, surface.viewDepth, sceneGridScale, entry);
            if (!valid) 
            {
                valid = FindGridEntry(surface.worldPos, gridNormal, surface.viewDepth, sceneGridScale, entry);
            }
            
            if (valid)
            {
                uint index = clamp(RAB_GetNextRandom(rng) * WORLD_SPACE_RESERVOIR_NUM_PER_GRID, 0, WORLD_SPACE_RESERVOIR_NUM_PER_GRID - 1);
                uint wsReservoirIndex = entry.gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + index;
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

    RTXDI_FinalizeResampling(state, 1.0, state.M);

    o_reservoir = state;
    o_lightSample = selectedLightSample;
    return entry.gridId;
}
#endif