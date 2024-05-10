#include "../../HelperFunctions.hlsli"
#include "../../ShaderParameters.h"

RWStructuredBuffer<RTXDI_PackedDIReservoir> u_WorldSpaceLightReservoirs : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 GlobalIndex : SV_DispatchThreadID)
{
    if (GlobalIndex.x >= WORLD_GRID_SIZE) return;

    RTXDI_PackedDIReservoir data = (RTXDI_PackedDIReservoir)0;

    for (uint i = 0; i < WORLD_SPACE_RESERVOIR_NUM_PER_GRID; ++i)
    {
        uint index = GlobalIndex.x * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + i;
        u_WorldSpaceLightReservoirs[index] = data;
    }
}