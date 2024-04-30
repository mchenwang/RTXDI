#include "../../ShaderParameters.h"

ByteAddressBuffer t_EnvGuidingStats : register(t0);
RWByteAddressBuffer u_IndirectParamsBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 GlobalIndex : SV_DispatchThreadID)
{
    uint rayCnt = min(t_EnvGuidingStats.Load(0), ENV_GUID_MAX_TEMP_RAY_NUM);
    u_IndirectParamsBuffer.Store3(0, uint3(ceil(rayCnt * 1.f / 64), 1, 1));
}