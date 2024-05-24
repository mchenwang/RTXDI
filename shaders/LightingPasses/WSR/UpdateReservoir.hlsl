#pragma pack_matrix(row_major)

#include "../RtxdiApplicationBridge.hlsli"
#include <rtxdi/DIResamplingFunctions.hlsli>

#include "Helper.hlsli"

// groupshared RTXDI_DIReservoir reservoir_cache[WORLD_SPACE_RESERVOIR_NUM_PER_GRID];
groupshared uint surface_id_cache[WORLD_SPACE_RESERVOIR_NUM_PER_GRID];

[numthreads(WORLD_SPACE_RESERVOIR_NUM_PER_GRID, 1, 1)]
void main(uint3 GlobalIndex : SV_DispatchThreadID, uint3 Gid : SV_GroupID, uint3 GTid : SV_GroupThreadID)
{
    if (Gid.x >= WORLD_SPACE_UPDATABLE_GRID_PER_FRAME_MAX_NUM) return;

    const uint maxSampleNum = t_WorldSpacePassIndirectParamsBuffer.Load(28);
    const uint iterateCnt   = t_WorldSpacePassIndirectParamsBuffer.Load(12);

    uint gridId = u_WorldSpaceReservoirUpdateGridQueue[Gid.x];

    WSRGridStats stats = u_WorldSpaceGridStatsBuffer[gridId];

    RAB_RandomSamplerState rng = WSR_InitRandomSampler(uint2(Gid.x, GTid.x), iterateCnt + 11 * 13);
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

    RAB_Surface newSurface = UnpackWSRSurface(t_WorldSpaceReorderedLightSamplesBuffer[surface_id_cache[GTid.x]].surface);
    RTXDI_DIReservoir newReservoir = RTXDI_EmptyDIReservoir();

    for (uint i = 0; i < WORLD_SPACE_LIGHT_SAMPLE_NUM_PER_RESERVOIR; ++i)
    {
        uint sampleIndex = clamp(floor(RAB_GetNextRandom(rng) * sampleCnt), 0, sampleCnt - 1) + stats.offset;
        
        WSRLightSample wsLightSample = t_WorldSpaceReorderedLightSamplesBuffer[sampleIndex];
        
        RAB_LightInfo lightInfo = RAB_LoadLightInfo(wsLightSample.lightIndex, false);

        RAB_LightSample lightSample = RAB_SamplePolymorphicLight(lightInfo, newSurface, wsLightSample.uv);
        
        float targetPdf = RAB_GetLightSampleTargetPdfForSurface(lightSample, newSurface);
        RTXDI_StreamSample(newReservoir, wsLightSample.lightIndex, wsLightSample.uv, RAB_GetNextRandom(rng), targetPdf, wsLightSample.invSourcePdf);
    }
    RTXDI_FinalizeResampling(newReservoir, 1.0, newReservoir.M);

    if (!(g_Const.worldSpaceReservoirFlag & WORLD_SPACE_RESERVOIR_REUSE))
    {
        u_WorldSpaceLightReservoirs[reservoirIndex].packedSurface = PackWSRSurface(newSurface);
        u_WorldSpaceLightReservoirs[reservoirIndex].packedReservoir = RTXDI_PackDIReservoir(newReservoir);
        return;
    }

    {
        RAB_Surface surface = (RAB_Surface)0;
        RAB_Surface preSurface = UnpackWSRSurface(u_WorldSpaceLightReservoirs[reservoirIndex].packedSurface);

        RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
        RTXDI_DIReservoir preReservoir = RTXDI_UnpackDIReservoir(u_WorldSpaceLightReservoirs[reservoirIndex].packedReservoir);

        preReservoir.M = min(preReservoir.M, 20 * newReservoir.M);
        {
            if (preReservoir.age < 30)
            {
                RTXDI_CombineDIReservoirs(state, preReservoir, 0.5f, preReservoir.targetPdf);

                surface = preSurface;

                RAB_LightSample newLightSample = RAB_SamplePolymorphicLight(
                    RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(newReservoir), false),
                    surface, RTXDI_GetDIReservoirSampleUV(newReservoir));

                bool selected = false;
                float targetPdf = RAB_GetLightSampleTargetPdfForSurface(newLightSample, surface);
                if(RTXDI_CombineDIReservoirs(state, newReservoir, RAB_GetNextRandom(rng), targetPdf))
                {
                    selected = true;
                }
            }
            else
            {
                RTXDI_CombineDIReservoirs(state, newReservoir, 0.5f, newReservoir.targetPdf);

                surface = newSurface;

                RAB_LightSample preLightSample = RAB_SamplePolymorphicLight(
                    RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(preReservoir), false),
                    surface, RTXDI_GetDIReservoirSampleUV(preReservoir));

                bool selected = false;
                float targetPdf = RAB_GetLightSampleTargetPdfForSurface(preLightSample, surface);
                if(RTXDI_CombineDIReservoirs(state, preReservoir, RAB_GetNextRandom(rng), targetPdf))
                {
                    selected = true;
                }
            }
            RTXDI_FinalizeResampling(state, 1, state.M);
        }
        
        state.age++;

        u_WorldSpaceLightReservoirs[reservoirIndex].packedSurface = PackWSRSurface(newSurface);
        u_WorldSpaceLightReservoirs[reservoirIndex].packedReservoir = RTXDI_PackDIReservoir(state);
        return;
    }
    

    RAB_Surface surface = (RAB_Surface)0;
    RAB_Surface preSurface = UnpackWSRSurface(u_WorldSpaceLightReservoirs[reservoirIndex].packedSurface);

    RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    RTXDI_DIReservoir preReservoir = RTXDI_UnpackDIReservoir(u_WorldSpaceLightReservoirs[reservoirIndex].packedReservoir);

    // RTXDI_CombineDIReservoirs(state, preReservoir, 0.5f, preReservoir.targetPdf);
    // if (RTXDI_CombineDIReservoirs(state, newReservoir, RAB_GetNextRandom(rng), newReservoir.targetPdf))
    // {
    //     surface = newSurface;
    // }
    // else
    // {
    //     surface = preSurface;
    // }
    // RTXDI_FinalizeResampling(state, 1.0, state.M);

    // u_WorldSpaceLightReservoirs[reservoirIndex].packedSurface = PackWSRSurface(surface);
    // u_WorldSpaceLightReservoirs[reservoirIndex].packedReservoir = RTXDI_PackDIReservoir(state);
    // return;

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
            targetPdf = newReservoir.targetPdf;
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
            targetPdf = preReservoir.targetPdf;
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
}