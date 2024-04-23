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

void SampleEnvRadianceMap(
    in EnvGuidingData guidedData,
    in float2 xi,
    out float3 o_w,
    out float pdf)
{
    uint index = 0;
    float cdf = 0.f;
    for (; index < ENV_GUID_RESOLUTION * ENV_GUID_RESOLUTION; ++index)
    {
        cdf += guidedData.luminance[index];
        if (cdf > xi.x) break;
    }
    index = clamp(index, 0, ENV_GUID_RESOLUTION * ENV_GUID_RESOLUTION - 1);

    xi.x = (xi.x - (cdf - guidedData.luminance[index])) / (guidedData.luminance[index]);

    float2 tex = float2(index % ENV_GUID_RESOLUTION, floor(index * 1.f / ENV_GUID_RESOLUTION)) + xi;
    tex /= float2(ENV_GUID_RESOLUTION, ENV_GUID_RESOLUTION);
    o_w = DecodeHemioct(tex * 2.f - 1.f);
    pdf = guidedData.luminance[index];
}

float GetEnvRadiancGuidedPdf(in EnvGuidingData guidedData, in float3 w)
{
    float2 tex = EncodeHemioct(w) * 0.5f + 0.5f;
    int2 pixel = floor(tex * float2(ENV_GUID_RESOLUTION, ENV_GUID_RESOLUTION));
    uint index = pixel.x + pixel.y * ENV_GUID_RESOLUTION;
    return guidedData.luminance[index];
}

#endif