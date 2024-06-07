#pragma pack_matrix(row_major)

#include "../RtxdiApplicationBridge.hlsli"
#include <rtxdi/DIResamplingFunctions.hlsli>

#include "Helper.hlsli"

[numthreads(64, 1, 1)]
void main(uint3 GlobalIndex : SV_DispatchThreadID, uint3 Gid : SV_GroupID, uint3 GTid : SV_GroupThreadID)
{
    if (GlobalIndex.x >= WORLD_SPACE_UPDATABLE_GRID_PER_FRAME_MAX_NUM) return;

    const uint iterateCnt   = t_WorldSpacePassIndirectParamsBuffer.Load(12);

    uint gridId = u_WorldSpaceReservoirUpdateGridQueue[GlobalIndex.x];

    RAB_RandomSamplerState rng = WSR_InitRandomSampler(uint2(GlobalIndex.x, GTid.x), iterateCnt + 10 * 13);

    uint reservoirIndexOffset = WORLD_GRID_SIZE * WORLD_SPACE_RESERVOIR_NUM_PER_GRID;
    uint aggregateIndex = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + reservoirIndexOffset;

    const uint auxiliaryNum = WORLD_SPACE_RESERVOIR_NUM_PER_GRID;

    RAB_Surface aggregateSurface = RAB_EmptySurface();
    RAB_Surface sampleSurfaces[auxiliaryNum];

    uint i = 0;

    for (i = 0; i < auxiliaryNum; ++i)
    {
        sampleSurfaces[i] = UnpackWSRSurface(u_WorldSpaceReservoirSurface[aggregateIndex + i + 1]);

        aggregateSurface.worldPos += sampleSurfaces[i].worldPos;
        aggregateSurface.normal += sampleSurfaces[i].normal;
        aggregateSurface.geoNormal += sampleSurfaces[i].geoNormal;
        aggregateSurface.diffuseAlbedo += sampleSurfaces[i].diffuseAlbedo;
        aggregateSurface.specularF0 += sampleSurfaces[i].specularF0;
        aggregateSurface.roughness += sampleSurfaces[i].roughness;
        aggregateSurface.diffuseProbability += sampleSurfaces[i].diffuseProbability;
    }

    aggregateSurface.worldPos *= 1.f / auxiliaryNum;
    aggregateSurface.diffuseAlbedo *= 1.f / auxiliaryNum;
    aggregateSurface.specularF0 *= 1.f / auxiliaryNum;
    aggregateSurface.roughness *= 1.f / auxiliaryNum;
    aggregateSurface.diffuseProbability *= 1.f / auxiliaryNum;

    aggregateSurface.normal = normalize(aggregateSurface.normal);
    aggregateSurface.geoNormal = normalize(aggregateSurface.geoNormal);

    aggregateSurface.viewDir = normalize(g_Const.view.cameraDirectionOrPosition.xyz - aggregateSurface.worldPos);

    float aggregateDistance = 0.f; // r
    float aggregateThetaN = 0.f;
    for (i = 0; i < auxiliaryNum; ++i)
    {
        aggregateDistance += distance(sampleSurfaces[i].worldPos, aggregateSurface.worldPos);
        aggregateThetaN += acos(dot(sampleSurfaces[i].normal, aggregateSurface.normal));
    }
    aggregateDistance *= 1.f / auxiliaryNum;
    aggregateThetaN *= 1.f / auxiliaryNum;

    RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    for (i = 0; i < auxiliaryNum; ++i)
    {
        RTXDI_DIReservoir auxiliaryReservoir = RTXDI_UnpackDIReservoir(u_WorldSpaceLightReservoirs[aggregateIndex + i + 1].packedReservoir);

        RAB_LightSample lightSample = RAB_EmptyLightSample();
        if (RTXDI_IsValidDIReservoir(auxiliaryReservoir))
        {
            lightSample = RAB_SamplePolymorphicLight(
                RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(auxiliaryReservoir), false),
                aggregateSurface, RTXDI_GetDIReservoirSampleUV(auxiliaryReservoir));
        }

        float weight = 0.f;
        if (RTXDI_IsValidDIReservoir(auxiliaryReservoir))
        {
            weight = WSR_GetLightSampleTargetDistributionForGrid(lightSample, aggregateSurface, aggregateDistance, aggregateThetaN);
        }
        RTXDI_CombineDIReservoirs(state, auxiliaryReservoir, RAB_GetNextRandom(rng), weight);
    }

    if (g_Const.worldSpaceReservoirFlag & WORLD_SPACE_RESERVOIR_TEMPORAL_REUSE)
    {
        uint preAggregateIndex = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID;

        RTXDI_DIReservoir preAggregateReservoir = RTXDI_UnpackDIReservoir(u_WorldSpaceLightReservoirs[preAggregateIndex].packedReservoir);

        RAB_LightSample lightSample = RAB_EmptyLightSample();
        preAggregateReservoir.M = min(preAggregateReservoir.M, state.M * 20);
        if (RTXDI_IsValidDIReservoir(preAggregateReservoir))
        {
            lightSample = RAB_SamplePolymorphicLight(
                RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(preAggregateReservoir), false),
                aggregateSurface, RTXDI_GetDIReservoirSampleUV(preAggregateReservoir));
        }

        float weight = 0.f;
        if (RTXDI_IsValidDIReservoir(preAggregateReservoir))
        {
            weight = WSR_GetLightSampleTargetDistributionForGrid(lightSample, aggregateSurface, aggregateDistance, aggregateThetaN);
        }
        RTXDI_CombineDIReservoirs(state, preAggregateReservoir, RAB_GetNextRandom(rng), weight);
    }

    RTXDI_FinalizeResampling(state, 1.0, state.M);
    // state.M = 1;
    
    u_WorldSpaceReservoirSurface[aggregateIndex] = PackWSRSurface(aggregateSurface);
    u_WorldSpaceLightReservoirs[aggregateIndex].packedReservoir = RTXDI_PackDIReservoir(state);
    return;
}