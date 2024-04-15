#ifndef ENV_VISIBILITY_HLSLI
#define ENV_VISIBILITY_HLSLI

#include "HashGridHelper.hlsli"

float2 GetSmeiSphereTexcoord(float3 local_p)
{
    float phi = atan2(local_p.y, local_p.x);
    phi = phi < 0.f ? phi + c_pi * 2.f : phi;
    float theta = acos(local_p.z);

    const float c_1_pi = 1.f / c_pi;
    return float2(phi * c_1_pi * 0.5f, theta * c_1_pi * 2.f);
}

uint GetInnerPixelIndexBySmeiSphereTexcoord(float2 tex)
{
    uint x = clamp(floor(tex.x * 6), 0, 5);
    uint y = clamp(floor(tex.y * 6), 0, 5);
    uint pixelIndex = y * 6 + x;

    return pixelIndex;
}

float3 GetLocalDirectionByInnerPixelIndex(uint index, float2 jitter)
{
    float2 texSphere;
    texSphere = (float2(index % 6, index / 6) + jitter) / float2(6.f, 6.f);

    float phi = texSphere.x * 2.f * c_pi;
    float theta = texSphere.y * 0.5f * c_pi;

    return float3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta));
}

float2 GetSphereTexcoordByInnerPixelIndex(uint index, float2 jitter)
{
    return (float2(index % 6, index / 6) + jitter) / float2(6.f, 6.f);
}


#ifdef RTXDI_APPLICATION_BRIDGE_HLSLI

bool SampleEnvVisibilityMap(RAB_Surface surface, inout RAB_RandomSamplerState rng, out float3 dir, out float pdf)
{
    uint hashId = GetUniformGridCellHashId(surface.worldPos, 0.5f);
    float xi = RAB_GetNextRandom(rng);
    float offset = hashId * 6 * 6;
    uint l = 0, r = 35;
    // while (l < r)
    // {
    //     uint m = (l + r) >> 1;
    //     if (u_EnvVisiblityCdfMap[offset + m] < xi) l = m + 1;
    //     else r = m;
    // }
    for (; l <= 35; ++l) if (u_EnvVisiblityCdfMap[offset + l] >= xi) break;
    // if (l > 35) return false;
    l = clamp(xi * 35, 0, 35);

    float2 jitter = float2(RAB_GetNextRandom(rng), RAB_GetNextRandom(rng));
    float3 dirLocal = GetLocalDirectionByInnerPixelIndex(l, jitter);

    float3 tangent, bitangent;
    branchlessONB(surface.normal, tangent, bitangent);

    dir = normalize(tangent * dirLocal.x + bitangent * dirLocal.y + surface.normal * dirLocal.z);
    pdf = u_EnvVisiblityCdfMap[offset + l] - 
        (l == 0 ? 0 : u_EnvVisiblityCdfMap[offset + l - 1]);

    return true;
}

bool SampleEnvVisibilityMap(RAB_Surface surface, inout RAB_RandomSamplerState rng, out float2 uv, out float pdf)
{
    uint hashId = GetUniformGridCellHashId(surface.worldPos, 0.5f);
    float xi = RAB_GetNextRandom(rng);
    float offset = hashId * 6 * 6;
    uint l = 0, r = 35;
    // while (l < r)
    // {
    //     uint m = (l + r) >> 1;
    //     if (u_EnvVisiblityCdfMap[offset + m] < xi) l = m + 1;
    //     else r = m;
    // }
    for (; l <= 35; ++l) if (u_EnvVisiblityCdfMap[offset + l] >= xi) break;
    // if (l > 35) return false;
    l = clamp(xi * 35, 0, 35);

    float2 jitter = float2(RAB_GetNextRandom(rng), RAB_GetNextRandom(rng));
    uv = GetSphereTexcoordByInnerPixelIndex(l, jitter);
    pdf = u_EnvVisiblityCdfMap[offset + l] - 
        (l == 0 ? 0 : u_EnvVisiblityCdfMap[offset + l - 1]);

    return true;
}

float GetVisibilityPdf(RAB_Surface surface, float3 dir)
{
    uint hashId = GetUniformGridCellHashId(surface.worldPos, 0.5f);
    float3 tangent, bitangent;
    branchlessONB(surface.normal, tangent, bitangent);
    float3 dirLocal = float3(dot(dir, tangent), dot(dir, bitangent), dot(dir, surface.normal));
    uint index = GetInnerPixelIndexBySmeiSphereTexcoord(GetSmeiSphereTexcoord(dirLocal));
    if (index == 0) return u_EnvVisiblityCdfMap[hashId * 6 * 6 + index];
    return u_EnvVisiblityCdfMap[hashId * 6 * 6 + index] - 
        (index == 0 ? 0 : u_EnvVisiblityCdfMap[hashId * 6 * 6 + index - 1]);
}

void UpdateVisibilityMap(RAB_Surface surface, float3 dir, bool visible)
{
    if (!visible) return;
    
    uint hashId = GetUniformGridCellHashId(surface.worldPos, 0.5f);

    float3 tangent, bitangent;
    branchlessONB(surface.normal, tangent, bitangent);
    float3 dirLocal = float3(dot(dir, tangent), dot(dir, bitangent), dot(dir, surface.normal));
    float2 texSphere = GetSmeiSphereTexcoord(dirLocal);

    uint pixelIndex = GetInnerPixelIndexBySmeiSphereTexcoord(texSphere);

    InterlockedAdd(u_EnvVisiblityDataMap[hashId].total_cnt, 1);
    InterlockedAdd(u_EnvVisiblityDataMap[hashId].local_cnt[pixelIndex], 1);
}

#endif
#endif