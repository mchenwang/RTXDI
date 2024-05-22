#ifndef WSR_SAMPLE_HELPERS_HLSLI
#define WSR_SAMPLE_HELPERS_HLSLI

#include <donut/shaders/utils.hlsli>
#include <donut/shaders/packing.hlsli>
#include "../../HelperFunctions.hlsli"

typedef RandomSamplerState RAB_RandomSamplerState;

RAB_RandomSamplerState RAB_InitRandomSampler(uint2 index, uint frameIndex)
{
    return initRandomSampler(index, frameIndex);
}

// Draws a random number X from the sampler, so that (0 <= X < 1).
float RAB_GetNextRandom(inout RAB_RandomSamplerState rng)
{
    return sampleUniformRng(rng);
}

struct RAB_Surface
{
    float3 worldPos;
    float3 viewDir;
    float viewDepth;
    float3 normal;
    float3 geoNormal;
    float3 diffuseAlbedo;
    float3 specularF0;
    float roughness;
    float diffuseProbability;
};

struct RAB_LightSample
{
    float3 position;
    float3 normal;
    float3 radiance;
    float solidAnglePdf;
    PolymorphicLightType lightType;
};

WSRSurfaceData PackWSRSurface(RAB_Surface surface)
{
    WSRSurfaceData packedSurface = (WSRSurfaceData)0;
    packedSurface.worldPos = surface.worldPos;
    packedSurface.normal = ndirToOctUnorm32(surface.normal);
    packedSurface.diffuseAlbedo = Pack_R11G11B10_UFLOAT(surface.diffuseAlbedo);
    packedSurface.specularAndRoughness = Pack_R8G8B8A8_Gamma_UFLOAT(float4(surface.specularF0, surface.roughness));
    packedSurface.viewDir = ndirToOctUnorm32(surface.viewDir);

    return packedSurface;
}

RAB_Surface UnpackWSRSurface(WSRSurfaceData packedSurface)
{
    RAB_Surface surface = (RAB_Surface)0;
    surface.worldPos = packedSurface.worldPos;
    surface.viewDepth = 1.0; // doesn't matter
    surface.normal = octToNdirUnorm32(packedSurface.normal);
    surface.geoNormal = surface.normal;
    surface.diffuseAlbedo = Unpack_R11G11B10_UFLOAT(packedSurface.diffuseAlbedo);
    float4 specularRough = Unpack_R8G8B8A8_Gamma_UFLOAT(packedSurface.specularAndRoughness);
    surface.specularF0 = specularRough.rgb;
    surface.roughness = specularRough.a;
    // surface.diffuseProbability = getSurfaceDiffuseProbability(surface);
    surface.viewDir = octToNdirUnorm32(packedSurface.viewDir);

    return surface;
}


float RAB_GetLightSampleTargetPdfForSurface(RAB_LightSample lightSample, RAB_Surface surface)
{
    if (lightSample.solidAnglePdf <= 0)
        return 0;

    float3 L = normalize(lightSample.position - surface.worldPos);

    if (dot(L, surface.geoNormal) <= 0)
        return 0;
    
    float3 V = surface.viewDir;
    // float3 V = reflect(-L, surface.normal);

    float d = Lambert(surface.normal, -L);
    float3 s = 0;
    if (surface.roughness == 0)
        s = 0;
    else
        s = GGX_times_NdotL(V, L, surface.normal, max(surface.roughness, 0.05f), surface.specularF0);

    float3 reflectedRadiance = lightSample.radiance * (d * surface.diffuseAlbedo + s);
    
    return calcLuminance(reflectedRadiance) / lightSample.solidAnglePdf;
}

#endif