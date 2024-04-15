#include "../ShaderParameters.h"

RWStructuredBuffer<EnvVisibilityMapData> u_EnvVisiblityDataMap : register(u0);
RWBuffer<float> u_EnvVisiblityCdfMap : register(u1);

[numthreads(32, 1, 1)] 
void main(uint2 GlobalIndex : SV_DispatchThreadID) 
{
    uint sum = 0;
    uint offset = GlobalIndex.x * 36;
    float invTotalCnt = 0.f;
    if (u_EnvVisiblityDataMap[GlobalIndex.x].total_cnt > 0) 
        invTotalCnt = 1.f / u_EnvVisiblityDataMap[GlobalIndex.x].total_cnt;

    for (uint i = 0; i < 36; ++i)
    {
        sum += u_EnvVisiblityDataMap[GlobalIndex.x].local_cnt[i];
        u_EnvVisiblityCdfMap[offset + i] = sum * invTotalCnt;
    }
}