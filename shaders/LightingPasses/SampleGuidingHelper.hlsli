#ifndef SAMPLE_GUIDING_HELPER_HLSLI
#define SAMPLE_GUIDING_HELPER_HLSLI

float GetvMFPdf(in vMF vmf, in float3 w)
{
    float eMin2Kappa = exp(-2.f * vmf.kappa);
    float de = 2 * c_pi * (1.f - eMin2Kappa);
    float pdfFactor = vmf.kappa / de;
    float t = dot(vmf.mu, w) - 1.f;
    float e = exp(vmf.kappa * t);
    return pdfFactor * e;
}

void SamplevMF(in vMF vmf, in float2 xi, out float3 o_w, out float o_pdf)
{
    float sinPhi, cosPhi;
    sincos(2.f * c_pi * xi.y, sinPhi, cosPhi);
    
    float eMin2Kappa = exp(-2.f * vmf.kappa);
    float value = xi.x + (1.f - xi.x) * eMin2Kappa;
    float cosTheta = clamp(1.f + log(value) / vmf.kappa, -1.f, 1.f);
    float sinTheta = sqrt(1.f - cosTheta * cosTheta);

    o_w = ToWorld(float3(sinTheta * cosPhi, sinTheta * sinPhi, cosTheta), vmf.mu);

    float de = 2 * c_pi * (1.f - eMin2Kappa);
    float e = exp(vmf.kappa * (dot(vmf.mu, o_w) - 1.f));
    o_pdf = vmf.kappa / de * e;
}

void UpdatevMFData(in uint vmfId, in vMFData data)
{
    if (u_vMFBuffer[vmfId].dataCnt < VMF_MAX_DATA_NUM)
    {
        uint index;
        InterlockedAdd(u_vMFBuffer[vmfId].dataCnt, 1, index);
        if (index < VMF_MAX_DATA_NUM)
            u_vMFDataBuffer[vmfId * VMF_MAX_DATA_NUM + index] = data;
    }
}

#endif