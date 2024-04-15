#include "../ShaderParameters.h"

RWStructuredBuffer<EnvVisibilityMapData> u_EnvVisiblityDataMap : register(u0);
RWBuffer<float> u_EnvVisiblityCdfMap : register(u1);

[numthreads(32, 1, 1)] 
void main(uint2 GlobalIndex : SV_DispatchThreadID) 
{
    uint offset = GlobalIndex.x * 36;
    u_EnvVisiblityDataMap[GlobalIndex.x].total_cnt = 0;
    
    for (uint i = 0; i < 36; ++i)
    {
        u_EnvVisiblityDataMap[GlobalIndex.x].local_cnt[i] = 0;
        u_EnvVisiblityCdfMap[offset + i] = 0.f;
    }
}