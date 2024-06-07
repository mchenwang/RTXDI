#pragma pack_matrix(row_major)

#include "../RtxdiApplicationBridge.hlsli"
#include <rtxdi/DIResamplingFunctions.hlsli>

#include "Helper.hlsli"

[numthreads(WORLD_SPACE_RESERVOIR_NUM_PER_GRID, 1, 1)]
void main(uint3 GlobalIndex : SV_DispatchThreadID, uint3 Gid : SV_GroupID, uint3 GTid : SV_GroupThreadID)
{
    if (Gid.x >= WORLD_SPACE_UPDATABLE_GRID_PER_FRAME_MAX_NUM) return;

    const uint iterateCnt = t_WorldSpacePassIndirectParamsBuffer.Load(12);
    RAB_RandomSamplerState rng = WSR_InitRandomSampler(uint2(Gid.x, GTid.x), iterateCnt + 11 * 13);

    uint gridId = u_WorldSpaceReservoirUpdateGridQueue[Gid.x];

    uint reservoirIndexOffset = WORLD_GRID_SIZE * WORLD_SPACE_RESERVOIR_NUM_PER_GRID;
    uint reservoirIndex = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + GTid.x;

    RAB_Surface preSurface = RAB_EmptySurface();
    RAB_Surface newSurface = UnpackWSRSurface(u_WorldSpaceReservoirSurface[reservoirIndex + reservoirIndexOffset]);
    RTXDI_DIReservoir newReservoir = RTXDI_UnpackDIReservoir(u_WorldSpaceLightReservoirs[reservoirIndex + reservoirIndexOffset].packedReservoir);
    
    RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    RTXDI_CombineDIReservoirs(state, newReservoir, 0.5f, newReservoir.targetPdf);

    float previousM = 0;
    int selectedLightPrevID = -1;
    bool selectedPreviousSample = false;
    // RAB_LightSample selectedLightSample = RAB_EmptyLightSample();

    // uint preReservoirIndexOffset = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID;
    for (uint i = 0; i < 1; ++i)
    {
        uint preReservoirIndex = reservoirIndex;
        // uint preReservoirIndex = gridId * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + i;
        //     // clamp(RAB_GetNextRandom(rng) * WORLD_SPACE_RESERVOIR_NUM_PER_GRID, 0, WORLD_SPACE_RESERVOIR_NUM_PER_GRID - 1);
        
        preSurface = UnpackWSRSurface(u_WorldSpaceReservoirSurface[preReservoirIndex]);
        preSurface.viewDir = normalize(g_Const.prevView.cameraDirectionOrPosition.xyz - preSurface.worldPos);

        if (dot(preSurface.normal, newSurface.normal) <= 0.8f) continue;
        if (length(preSurface.worldPos - newSurface.worldPos) >= 0.5f) continue;

        RTXDI_DIReservoir preReservoir = RTXDI_UnpackDIReservoir(u_WorldSpaceLightReservoirs[preReservoirIndex].packedReservoir);
        
        preReservoir.M = min(preReservoir.M, newReservoir.M * 20);
        previousM = preReservoir.M;
        
        uint originalPrevLightID = RTXDI_GetDIReservoirLightIndex(preReservoir);

        // preReservoir.M = 1;
        if (RTXDI_IsValidDIReservoir(preReservoir))
        {
            int mappedLightID = RAB_TranslateLightIndex(originalPrevLightID, false);

            if (mappedLightID < 0)
            {
                // Kill the reservoir
                preReservoir.weightSum = 0;
                preReservoir.lightData = 0;
            }
            else
            {
                // Sample is valid - modify the light ID stored
                preReservoir.lightData = mappedLightID | RTXDI_DIReservoir_LightValidBit;
            }
        }

        float temporalWeight = 0.f;
        RAB_LightSample candidateLightSample = RAB_EmptyLightSample();
        if (RTXDI_IsValidDIReservoir(preReservoir))
        {
            candidateLightSample = RAB_SamplePolymorphicLight(
                RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(preReservoir), false),
                newSurface, RTXDI_GetDIReservoirSampleUV(preReservoir));

            temporalWeight = RAB_GetLightSampleTargetPdfForSurface(candidateLightSample, newSurface);
        }

        if (RTXDI_CombineDIReservoirs(state, preReservoir, RAB_GetNextRandom(rng), temporalWeight))
        {
            selectedPreviousSample = true;
            selectedLightPrevID = int(originalPrevLightID);
            // selectedLightSample = candidateLightSample;
        }
    }

    // float pi = state.targetPdf;
    // float piSum = state.targetPdf * newReservoir.M;
    // if (RTXDI_IsValidDIReservoir(state) && selectedLightPrevID >= 0 && previousM > 0)
    // {
    //     float temporalP = 0;

    //     const RAB_LightInfo selectedLightPrev = RAB_LoadLightInfo(selectedLightPrevID, true);

    //     const RAB_LightSample selectedSampleAtTemporal = RAB_SamplePolymorphicLight(
    //         selectedLightPrev, preSurface, RTXDI_GetDIReservoirSampleUV(state));
    
    //     temporalP = RAB_GetLightSampleTargetPdfForSurface(selectedSampleAtTemporal, preSurface);
    //     if (!RAB_GetTemporalConservativeVisibility(newSurface, preSurface, selectedSampleAtTemporal))
    //     {
    //         temporalP = 0;
    //     }

    //     pi = selectedPreviousSample ? temporalP : pi;
    //     piSum += temporalP * previousM;

    // }
    // RTXDI_FinalizeResampling(state, pi, piSum);
    RTXDI_FinalizeResampling(state, 1, state.M);

    u_WorldSpaceLightReservoirs[reservoirIndex + reservoirIndexOffset].packedReservoir = RTXDI_PackDIReservoir(state);
}