#include "../ShaderParameters.h"

RWStructuredBuffer<vMF> u_vMFBuffer : register(u0);
RWStructuredBuffer<vMFData> u_vMFDataBuffer : register(u1);

[numthreads(32, 1, 1)] 
void main(uint2 GlobalIndex : SV_DispatchThreadID) 
{
    if (GlobalIndex.x >= WORLD_GRID_SIZE) return;

    vMF vmf = u_vMFBuffer[GlobalIndex.x];
    vmf.kappa = 0.f;
    vmf.dataCnt = 0;

    u_vMFBuffer[GlobalIndex.x] = vmf;
}