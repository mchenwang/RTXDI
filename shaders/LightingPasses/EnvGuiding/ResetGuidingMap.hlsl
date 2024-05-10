#include "../../HelperFunctions.hlsli"
#include "../../ShaderParameters.h"

RWStructuredBuffer<EnvGuidingData> u_EnvGuidingMap : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 GlobalIndex : SV_DispatchThreadID)
{
    if (GlobalIndex.x >= WORLD_GRID_SIZE) return;

    EnvGuidingData guidingData = (EnvGuidingData)0;
    u_EnvGuidingMap[GlobalIndex.x] = guidingData;
}