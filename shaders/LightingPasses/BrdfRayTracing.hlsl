/***************************************************************************
 # Copyright (c) 2020-2023, NVIDIA CORPORATION.  All rights reserved.
 #
 # NVIDIA CORPORATION and its licensors retain all intellectual property
 # and proprietary rights in and to this software, related documentation
 # and any modifications thereto.  Any use, reproduction, disclosure or
 # distribution of this software and related documentation without an express
 # license agreement from NVIDIA CORPORATION is strictly prohibited.
 **************************************************************************/

#pragma pack_matrix(row_major)

#include "RtxdiApplicationBridge.hlsli"

#include <rtxdi/DIResamplingFunctions.hlsli>

#ifdef WITH_NRD
#define NRD_HEADER_ONLY
#include <NRD.hlsli>
#endif

#include "ShadingHelpers.hlsli"
#include "HashGridHelper.hlsli"
#include "SampleGuidingHelper.hlsli"

static const float c_MaxIndirectRadiance = 10;

void GuidedSample(
    in RAB_Surface surface,
    in float3 V,
    in float3 tangent,
    in float3 bitangent,
    inout RAB_RandomSamplerState rng,
    out float3 o_L,
    out float3 o_BRDF_over_PDF,
    out bool o_isSpecularRay,
    out float o_overall_PDF,
    out float o_guidedSamplePdf)
{
    float2 Rand;
    Rand.x = RAB_GetNextRandom(rng);
    Rand.y = RAB_GetNextRandom(rng);
    
    bool isDeltaSurface = surface.roughness == 0;

    bool sampleBrdf = true;
    uint vmfId = ComputeSpatialHash(surface.worldPos);
    vMF vmf = u_vMFBuffer[vmfId];
    if (vmf.kappa > 0.f)
    {
        if (RAB_GetNextRandom(rng) < VMF_SAMPLE_FRACTION)
            sampleBrdf = false;
    }

    float3 brdf = 0.f;
    float vmfPdf = 0.f;

    if (sampleBrdf)
    {
        // float3 specularDirection;
        // float3 specular_BRDF_over_PDF;
        // {
            // float3 Ve = float3(dot(V, tangent), dot(V, bitangent), dot(V, surface.normal));
            // float3 He = sampleGGX_VNDF(Ve, surface.roughness, Rand);
            // float3 H = isDeltaSurface ? surface.normal : normalize(He.x * tangent + He.y * bitangent + He.z * surface.normal);
            // specularDirection = reflect(-V, H);

            // float HoV = saturate(dot(H, V));
            // float NoV = saturate(dot(surface.normal, V));
            // float3 F = Schlick_Fresnel(surface.specularF0, HoV);
            // float G1 = isDeltaSurface ? 1.0 : (NoV > 0) ? G1_Smith(surface.roughness, NoV) : 0;
            // specular_BRDF_over_PDF = F * G1;
        // }

        // float3 diffuseDirection;
        // float diffuse_BRDF_over_PDF;
        // {
            // float solidAnglePdf;
            // float3 localDirection = sampleCosHemisphere(Rand, solidAnglePdf);
            // diffuseDirection = tangent * localDirection.x + bitangent * localDirection.y + surface.normal * localDirection.z;
            // diffuse_BRDF_over_PDF = 1.0;
        // }

        // float specular_PDF = saturate(calcLuminance(specular_BRDF_over_PDF) /
            // calcLuminance(specular_BRDF_over_PDF + diffuse_BRDF_over_PDF * surface.diffuseAlbedo));

        // o_isSpecularRay = RAB_GetNextRandom(rng) < specular_PDF;

        // float specularLobe_PDF;
        // float diffuseLobe_PDF;

        // if (o_isSpecularRay)
        // {
            // o_L = specularDirection;

            // specularLobe_PDF = ImportanceSampleGGX_VNDF_PDF(surface.roughness, surface.normal, V, o_L);
            // diffuseLobe_PDF = saturate(dot(o_L, surface.normal)) / c_pi;
            
            // brdf = specular_BRDF_over_PDF * specularLobe_PDF;
            // o_guidedSamplePdf = specularLobe_PDF * specular_PDF;

            // o_BRDF_over_PDF = specular_BRDF_over_PDF / specular_PDF;
        // }
        // else
        // {
            // o_L = diffuseDirection;
            
            // specularLobe_PDF = ImportanceSampleGGX_VNDF_PDF(surface.roughness, surface.normal, V, o_L);
            // diffuseLobe_PDF = saturate(dot(o_L, surface.normal)) / c_pi;

            // brdf = diffuse_BRDF_over_PDF * diffuseLobe_PDF;
            // o_guidedSamplePdf = diffuseLobe_PDF * (1.f - specular_PDF);

            // o_BRDF_over_PDF = diffuse_BRDF_over_PDF / (1.f - specular_PDF);
        // }

        // For delta surfaces, we only pass the diffuse lobe to ReSTIR GI, and this pdf is for that.
        // o_overall_PDF = isDeltaSurface ? diffuseLobe_PDF : lerp(diffuseLobe_PDF, specularLobe_PDF, specular_PDF);

        
        float solidAnglePdf;
        float3 localDirection = sampleCosHemisphere(Rand, solidAnglePdf);
        o_L = tangent * localDirection.x + bitangent * localDirection.y + surface.normal * localDirection.z;
        o_BRDF_over_PDF = 1.f;

        const float diffuseLobe_PDF = saturate(dot(o_L, surface.normal)) / c_pi;

        o_guidedSamplePdf = diffuseLobe_PDF;

        o_overall_PDF = diffuseLobe_PDF;

        if (vmf.kappa > 0.f)
        {
            vmfPdf = GetvMFPdf(vmf, o_L);
            o_guidedSamplePdf = o_guidedSamplePdf * (1.f - VMF_SAMPLE_FRACTION) + vmfPdf * VMF_SAMPLE_FRACTION;
        }
    }
    else
    {
        SamplevMF(vmf, Rand, o_L, vmfPdf);

        // float specularLobe_PDF = ImportanceSampleGGX_VNDF_PDF(surface.roughness, surface.normal, V, o_L);
        float diffuseLobe_PDF = saturate(dot(o_L, surface.normal)) / c_pi;

        // float3 specularDirection = reflect(-V, surface.normal);
        // o_isSpecularRay = (abs(dot(specularDirection, o_L) - 1.f) < 1e-5);
        // o_isSpecularRay = isDeltaSurface;
        
        // float3 specular_BRDF_over_PDF;
        // {
            // float3 H = normalize(o_L + V);
            // float HoV = saturate(dot(H, V));
            // float NoV = saturate(dot(surface.normal, V));
            // float3 F = Schlick_Fresnel(surface.specularF0, HoV);
            // float G1 = isDeltaSurface ? 1.0 : (NoV > 0) ? G1_Smith(surface.roughness, NoV) : 0;
            // specular_BRDF_over_PDF = F * G1;
        // }

        float diffuse_BRDF_over_PDF = 1.0;

        // float specular_PDF = saturate(calcLuminance(specular_BRDF_over_PDF) /
        //     calcLuminance(specular_BRDF_over_PDF + diffuse_BRDF_over_PDF * surface.diffuseAlbedo));

        // brdf = specular_BRDF_over_PDF * specularLobe_PDF + diffuse_BRDF_over_PDF * diffuseLobe_PDF;
        // o_guidedSamplePdf = diffuseLobe_PDF * (1.f - specular_PDF) + specularLobe_PDF * specular_PDF;
        // o_guidedSamplePdf *= vmfPdf;

        brdf = diffuse_BRDF_over_PDF * diffuseLobe_PDF;// * surface.diffuseAlbedo;
        
        // o_BRDF_over_PDF = brdf / max(o_guidedSamplePdf, 0.001);

        o_guidedSamplePdf = diffuseLobe_PDF;

        o_overall_PDF = diffuseLobe_PDF;

        o_guidedSamplePdf = o_guidedSamplePdf * (1.f - VMF_SAMPLE_FRACTION) + vmfPdf * VMF_SAMPLE_FRACTION;
        
        o_BRDF_over_PDF = brdf / o_guidedSamplePdf;
        
        // if (o_isSpecularRay)
        // {
            // brdf = specular_BRDF_over_PDF * specularLobe_PDF;
            // o_guidedSamplePdf = specularLobe_PDF * vmfPdf;

            // o_BRDF_over_PDF = specular_BRDF_over_PDF / vmfPdf;
        // }
        // else
        // {
            // brdf = diffuse_BRDF_over_PDF * diffuseLobe_PDF;
            // o_guidedSamplePdf = diffuseLobe_PDF * vmfPdf;

            // o_BRDF_over_PDF = diffuse_BRDF_over_PDF / vmfPdf;
        // }
    }

    // if (vmf.kappa > 0.f)
    //     o_guidedSamplePdf = o_guidedSamplePdf * (1.f - VMF_SAMPLE_FRACTION) + vmfPdf * VMF_SAMPLE_FRACTION;

    // o_BRDF_over_PDF = brdf / max(o_guidedSamplePdf, 0.001);
}

#if USE_RAY_QUERY
[numthreads(RTXDI_SCREEN_SPACE_GROUP_SIZE, RTXDI_SCREEN_SPACE_GROUP_SIZE, 1)]
void main(uint2 GlobalIndex : SV_DispatchThreadID)
#else
[shader("raygeneration")]
void RayGen()
#endif
{
#if !USE_RAY_QUERY
    uint2 GlobalIndex = DispatchRaysIndex().xy;
#endif
    uint2 pixelPosition = RTXDI_ReservoirPosToPixelPos(GlobalIndex, g_Const.runtimeParams.activeCheckerboardField);

    RAB_Surface surface = RAB_GetGBufferSurface(pixelPosition, false);

    if (!RAB_IsSurfaceValid(surface))
        return;

    RAB_RandomSamplerState rng = RAB_InitRandomSampler(GlobalIndex, 5);
    
    float3 tangent, bitangent;
    branchlessONB(surface.normal, tangent, bitangent);

    float distance = max(1, 0.1 * length(surface.worldPos - g_Const.view.cameraDirectionOrPosition.xyz));

    RayDesc ray;
    ray.TMin = 0.001f * distance;
    ray.TMax = 1000;

    float3 V = normalize(g_Const.view.cameraDirectionOrPosition.xyz - surface.worldPos);

    bool isSpecularRay = false;
    bool isDeltaSurface = surface.roughness == 0;
    float3 BRDF_over_PDF = 0.f;
    float overall_PDF;

    float guidedSamplePdf = 0.f;

    if (g_Const.guidingFlag & GUIDING_FLAG_GUIDE_DI)
    {
        GuidedSample(surface, V, tangent, bitangent, rng, 
            ray.Direction, BRDF_over_PDF, isSpecularRay, overall_PDF, guidedSamplePdf);
    }
    else
    {
        float2 Rand;
        Rand.x = RAB_GetNextRandom(rng);
        Rand.y = RAB_GetNextRandom(rng);

        float solidAnglePdf;
        float3 localDirection = sampleCosHemisphere(Rand, solidAnglePdf);
        ray.Direction = tangent * localDirection.x + bitangent * localDirection.y + surface.normal * localDirection.z;
        BRDF_over_PDF = 1.f;

        const float diffuseLobe_PDF = saturate(dot(ray.Direction, surface.normal)) / c_pi;

        guidedSamplePdf = diffuseLobe_PDF;

        overall_PDF = diffuseLobe_PDF;

        // float3 specularDirection;
        // float3 specular_BRDF_over_PDF;
        // {
        //     float3 Ve = float3(dot(V, tangent), dot(V, bitangent), dot(V, surface.normal));
        //     float3 He = sampleGGX_VNDF(Ve, surface.roughness, Rand);
        //     float3 H = isDeltaSurface ? surface.normal : normalize(He.x * tangent + He.y * bitangent + He.z * surface.normal);
        //     specularDirection = reflect(-V, H);

        //     float HoV = saturate(dot(H, V));
        //     float NoV = saturate(dot(surface.normal, V));
        //     float3 F = Schlick_Fresnel(surface.specularF0, HoV);
        //     float G1 = isDeltaSurface ? 1.0 : (NoV > 0) ? G1_Smith(surface.roughness, NoV) : 0;
        //     specular_BRDF_over_PDF = F * G1;
        // }

        // float3 diffuseDirection;
        // float diffuse_BRDF_over_PDF;
        // {
        //     float solidAnglePdf;
        //     float3 localDirection = sampleCosHemisphere(Rand, solidAnglePdf);
        //     diffuseDirection = tangent * localDirection.x + bitangent * localDirection.y + surface.normal * localDirection.z;
        //     diffuse_BRDF_over_PDF = 1.0;
        // }

        // float specular_PDF = saturate(calcLuminance(specular_BRDF_over_PDF) /
        //     calcLuminance(specular_BRDF_over_PDF + diffuse_BRDF_over_PDF * surface.diffuseAlbedo));

        // isSpecularRay = RAB_GetNextRandom(rng) < specular_PDF;

        // if (isSpecularRay)
        // {
        //     ray.Direction = specularDirection;
        //     BRDF_over_PDF = specular_BRDF_over_PDF / specular_PDF;
        // }
        // else
        // {
        //     ray.Direction = diffuseDirection;
        //     BRDF_over_PDF = diffuse_BRDF_over_PDF / (1.0 - specular_PDF);
        // }

        // const float specularLobe_PDF = ImportanceSampleGGX_VNDF_PDF(surface.roughness, surface.normal, V, ray.Direction);
        // const float diffuseLobe_PDF = saturate(dot(ray.Direction, surface.normal)) / c_pi;

        // if (isSpecularRay)
        // {
        //     guidedSamplePdf = specular_PDF * specularLobe_PDF;
        // }
        // else
        // {
        //     guidedSamplePdf = (1.f - specular_PDF) * diffuseLobe_PDF;
        // }

        // // For delta surfaces, we only pass the diffuse lobe to ReSTIR GI, and this pdf is for that.
        // overall_PDF = isDeltaSurface ? diffuseLobe_PDF : lerp(diffuseLobe_PDF, specularLobe_PDF, specular_PDF);
    }

    if (dot(surface.geoNormal, ray.Direction) <= 0.0)
    {
        BRDF_over_PDF = 0.0;
        ray.TMax = 0;
    }

    ray.Origin = surface.worldPos;
    u_DebugColor1[pixelPosition] = float4(BRDF_over_PDF, 1.f);

    if (any(BRDF_over_PDF <= 0)) return;

    float3 radiance = 0;
    
    RayPayload payload = (RayPayload)0;
    payload.instanceID = ~0u;
    payload.throughput = 1.0;

    uint instanceMask = INSTANCE_MASK_OPAQUE;
    
    if (g_Const.sceneConstants.enableAlphaTestedGeometry)
        instanceMask |= INSTANCE_MASK_ALPHA_TESTED;

    if (g_Const.sceneConstants.enableTransparentGeometry)
        instanceMask |= INSTANCE_MASK_TRANSPARENT;

#if USE_RAY_QUERY
    RayQuery<RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES> rayQuery;
    
    rayQuery.TraceRayInline(SceneBVH, RAY_FLAG_NONE, instanceMask, ray);

    while (rayQuery.Proceed())
    {
        if (rayQuery.CandidateType() == CANDIDATE_NON_OPAQUE_TRIANGLE)
        {
            if (considerTransparentMaterial(
                rayQuery.CandidateInstanceID(),
                rayQuery.CandidateGeometryIndex(),
                rayQuery.CandidatePrimitiveIndex(),
                rayQuery.CandidateTriangleBarycentrics(),
                payload.throughput))
            {
                rayQuery.CommitNonOpaqueTriangleHit();
            }
        }
    }

    if (rayQuery.CommittedStatus() == COMMITTED_TRIANGLE_HIT)
    {
        payload.instanceID = rayQuery.CommittedInstanceID();
        payload.geometryIndex = rayQuery.CommittedGeometryIndex();
        payload.primitiveIndex = rayQuery.CommittedPrimitiveIndex();
        payload.barycentrics = rayQuery.CommittedTriangleBarycentrics();
        payload.committedRayT = rayQuery.CommittedRayT();
    }
#else
    TraceRay(SceneBVH, RAY_FLAG_NONE, instanceMask, 0, 0, 0, ray, payload);
#endif

    if (g_PerPassConstants.rayCountBufferIndex >= 0)
    {
        InterlockedAdd(u_RayCountBuffer[RAY_COUNT_TRACED(g_PerPassConstants.rayCountBufferIndex)], 1);
    }

    uint gbufferIndex = RTXDI_ReservoirPositionToPointer(g_Const.restirGI.reservoirBufferParams, GlobalIndex, 0);
    
    struct 
    {
        float3 position;
        float3 normal;
        float3 diffuseAlbedo;
        float3 specularF0;
        float roughness;
        bool isEnvironmentMap;
    } secondarySurface;

    // Include the emissive component of surfaces seen with BRDF rays if requested (i.e. when Direct Lighting mode
    // is set to BRDF) or on delta reflection rays because those bypass ReSTIR GI and direct specular lighting,
    // and we need to see reflections of lamps and the sky in mirrors.
    const bool includeEmissiveComponent = g_Const.brdfPT.enableIndirectEmissiveSurfaces || (isSpecularRay && isDeltaSurface);

    if (payload.instanceID != ~0u)
    {
        if (g_PerPassConstants.rayCountBufferIndex >= 0)
        {
            InterlockedAdd(u_RayCountBuffer[RAY_COUNT_HITS(g_PerPassConstants.rayCountBufferIndex)], 1);
        }

        GeometrySample gs = getGeometryFromHit(
            payload.instanceID,
            payload.geometryIndex,
            payload.primitiveIndex,
            payload.barycentrics,
            GeomAttr_Normal | GeomAttr_TexCoord | GeomAttr_Position,
            t_InstanceData, t_GeometryData, t_MaterialConstants);
        
        MaterialSample ms = sampleGeometryMaterial(gs, 0, 0, 0,
            MatAttr_BaseColor | MatAttr_Emissive | MatAttr_MetalRough, s_MaterialSampler);

        ms.shadingNormal = getBentNormal(gs.flatNormal, ms.shadingNormal, ray.Direction);

        if (g_Const.brdfPT.materialOverrideParams.roughnessOverride >= 0)
            ms.roughness = g_Const.brdfPT.materialOverrideParams.roughnessOverride;

        if (g_Const.brdfPT.materialOverrideParams.metalnessOverride >= 0)
        {
            ms.metalness = g_Const.brdfPT.materialOverrideParams.metalnessOverride;
            getReflectivity(ms.metalness, ms.baseColor, ms.diffuseAlbedo, ms.specularF0);
        }

        ms.roughness = max(ms.roughness, g_Const.brdfPT.materialOverrideParams.minSecondaryRoughness);

        if (includeEmissiveComponent)
            radiance += ms.emissiveColor;

        secondarySurface.position = ray.Origin + ray.Direction * payload.committedRayT;
        secondarySurface.normal = (dot(gs.geometryNormal, ray.Direction) < 0) ? gs.geometryNormal : -gs.geometryNormal;
        secondarySurface.diffuseAlbedo = ms.diffuseAlbedo;
        secondarySurface.specularF0 = ms.specularF0;
        secondarySurface.roughness = ms.roughness;
        secondarySurface.isEnvironmentMap = false;
    }
    else
    {
        if (g_Const.sceneConstants.enableEnvironmentMap && includeEmissiveComponent)
        {
            float3 environmentRadiance = GetEnvironmentRadiance(ray.Direction);
            radiance += environmentRadiance;
        }

        secondarySurface.position = ray.Origin + ray.Direction * DISTANT_LIGHT_DISTANCE;
        secondarySurface.normal = -ray.Direction;
        secondarySurface.diffuseAlbedo = 0;
        secondarySurface.specularF0 = 0;
        secondarySurface.roughness = 0;
        secondarySurface.isEnvironmentMap = true;

        if (g_Const.guidingFlag & GUIDING_FLAG_UPDATE_ENABLE)
        {
            uint vmfId = ComputeSpatialHash(surface.worldPos);

            vMFData data = (vMFData)0;
            data.dir = ray.Direction;
            data.pdf = guidedSamplePdf;
            data.radianceLuminance = calcLuminance(payload.throughput * radiance * BRDF_over_PDF);

            UpdatevMFData(vmfId, data);
        }
    }

    if (g_Const.enableBrdfIndirect)
    {
        SecondaryGBufferData secondaryGBufferData = (SecondaryGBufferData)0;
        secondaryGBufferData.worldPos = secondarySurface.position;
        secondaryGBufferData.normal = ndirToOctUnorm32(secondarySurface.normal);
        secondaryGBufferData.throughputAndFlags = Pack_R16G16B16A16_FLOAT(float4(payload.throughput * BRDF_over_PDF, 0));
        secondaryGBufferData.diffuseAlbedo = Pack_R11G11B10_UFLOAT(secondarySurface.diffuseAlbedo);
        secondaryGBufferData.specularAndRoughness = Pack_R8G8B8A8_Gamma_UFLOAT(float4(secondarySurface.specularF0, secondarySurface.roughness));

        if (g_Const.brdfPT.enableReSTIRGI)
        {
            if (isSpecularRay && isDeltaSurface)
            {
                // Special case for specular rays on delta surfaces: they bypass ReSTIR GI and are shaded
                // entirely in the ShadeSecondarySurfaces pass, so they need the right throughput here.
            }
            else
            {
                // BRDF_over_PDF will be multiplied after resampling GI reservoirs.
                secondaryGBufferData.throughputAndFlags = Pack_R16G16B16A16_FLOAT(float4(payload.throughput, 0));
            }

            // The emission from the secondary surface needs to be added when creating the initial
            // GI reservoir sample in ShadeSecondarySurface.hlsl. It need to be stored separately.
            secondaryGBufferData.emission = radiance;
            radiance = 0;
            
            secondaryGBufferData.pdf = overall_PDF;
        }
        
        uint flags = 0;
        if (isSpecularRay) flags |= kSecondaryGBuffer_IsSpecularRay;
        if (isDeltaSurface) flags |= kSecondaryGBuffer_IsDeltaSurface;
        if (secondarySurface.isEnvironmentMap) flags |= kSecondaryGBuffer_IsEnvironmentMap;
        secondaryGBufferData.throughputAndFlags.y |= flags << 16;

        u_SecondaryGBuffer[gbufferIndex] = secondaryGBufferData;
    }

    if (any(radiance > 0) || !g_Const.enableBrdfAdditiveBlend)
    {
        radiance *= payload.throughput;

        float3 diffuse = isSpecularRay ? 0.0 : radiance * BRDF_over_PDF;
        float3 specular = isSpecularRay ? radiance * BRDF_over_PDF : 0.0;
        float diffuseHitT = payload.committedRayT;
        float specularHitT = payload.committedRayT;

        specular = DemodulateSpecular(surface.specularF0, specular);


        StoreShadingOutput(GlobalIndex, pixelPosition,
            surface.viewDepth, surface.roughness, diffuse, specular, payload.committedRayT, !g_Const.enableBrdfAdditiveBlend, !g_Const.enableBrdfIndirect);
    }
}
