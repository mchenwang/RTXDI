#include "../ShaderParameters.h"

RWStructuredBuffer<vMF> u_vMFBuffer : register(u0);
RWStructuredBuffer<vMFData> u_vMFDataBuffer : register(u1);

[numthreads(32, 1, 1)] 
void main(uint2 GlobalIndex : SV_DispatchThreadID) 
{
    if (GlobalIndex.x >= WORLD_GRID_SIZE) return;
    vMF vmf = u_vMFBuffer[GlobalIndex.x];
    if (vmf.dataCnt == 0) return;
    
    float weightSum = 0;
    float3 weightDirSum = 0;

    for (int i = 0; i < min(vmf.dataCnt, VMF_MAX_DATA_NUM); ++i)
    {
        vMFData data = u_vMFDataBuffer[GlobalIndex.x * VMF_MAX_DATA_NUM + i];
        if (data.radianceLuminance > 0.f && data.pdf > 0.f)
        {
            float weight = data.radianceLuminance / data.pdf;
            weightSum += weight;
            weightDirSum += weight * data.dir;
        }
    }

    if (weightSum <= 0.f) return;

    // compute previous sufficient statistics
    float preWeightSum = 0;
    float3 preWeightDirSum = 0;
    if (vmf.iterationCnt > 0) {
        // this pixel has a valid history, reuse the model
        preWeightSum = vmf.weightSum;
        preWeightDirSum = preWeightSum * vmf.meanCosine * vmf.mu;
    }

    // step-wise EM
    vmf.iterationCnt += 1;
    float movingWeight = 1.f / vmf.iterationCnt;
    weightSum = (1.f - movingWeight) * preWeightSum + movingWeight * weightSum;
    weightDirSum = (1.f - movingWeight) * preWeightDirSum + movingWeight * weightDirSum;
    // float weightSum = weightSum;
    // float3 weightDirSum = weightDirSum;

    float r_length = length(weightDirSum);

    // in case of singularity
    if (weightSum <= 0 || r_length <= 0) {
        return;
    }

    // update the model
    float mc = r_length / weightSum;
    vmf.mu = weightDirSum / r_length;
    vmf.kappa = clamp(mc * (3 - mc * mc) / (1 - mc * mc), 1e-2, 1e3);
    vmf.meanCosine = mc;
    vmf.weightSum = weightSum;
    vmf.dataCnt = 0;

    u_vMFBuffer[GlobalIndex.x] = vmf;
}