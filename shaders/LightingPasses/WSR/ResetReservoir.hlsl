#include "../../HelperFunctions.hlsli"
#include "../../ShaderParameters.h"

RWStructuredBuffer<WorldSpaceDIReservoir> u_WorldSpaceLightReservoirs : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 GlobalIndex : SV_DispatchThreadID)
{
    if (GlobalIndex.x >= WORLD_GRID_SIZE) return;

    WorldSpaceDIReservoir data = (WorldSpaceDIReservoir)0;

    for (uint i = 0; i < WORLD_SPACE_RESERVOIR_NUM_PER_GRID; ++i)
    {
        uint index = GlobalIndex.x * WORLD_SPACE_RESERVOIR_NUM_PER_GRID + i;
        u_WorldSpaceLightReservoirs[index] = data;
    }
}