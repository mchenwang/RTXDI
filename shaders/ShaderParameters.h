/***************************************************************************
 # Copyright (c) 2020-2023, NVIDIA CORPORATION.  All rights reserved.
 #
 # NVIDIA CORPORATION and its licensors retain all intellectual property
 # and proprietary rights in and to this software, related documentation
 # and any modifications thereto.  Any use, reproduction, disclosure or
 # distribution of this software and related documentation without an express
 # license agreement from NVIDIA CORPORATION is strictly prohibited.
 **************************************************************************/

#ifndef SHADER_PARAMETERS_H
#define SHADER_PARAMETERS_H

#include <donut/shaders/view_cb.h>
#include <donut/shaders/sky_cb.h>

#include <rtxdi/ReSTIRDIParameters.h>
#include <rtxdi/ReGIRParameters.h>
#include <rtxdi/ReSTIRGIParameters.h>

#include "BRDFPTParameters.h"

#define TASK_PRIMITIVE_LIGHT_BIT 0x80000000u

#define RTXDI_PRESAMPLING_GROUP_SIZE 256
#define RTXDI_GRID_BUILD_GROUP_SIZE 256
#define RTXDI_SCREEN_SPACE_GROUP_SIZE 8
#define RTXDI_GRAD_FACTOR 3
#define RTXDI_GRAD_STORAGE_SCALE 256.0f
#define RTXDI_GRAD_MAX_VALUE 65504.0f

#define INSTANCE_MASK_OPAQUE 0x01
#define INSTANCE_MASK_ALPHA_TESTED 0x02
#define INSTANCE_MASK_TRANSPARENT 0x04
#define INSTANCE_MASK_ALL 0xFF

#define DENOISER_MODE_OFF 0
#define DENOISER_MODE_REBLUR 1
#define DENOISER_MODE_RELAX 2

#define VIS_MODE_NONE                0
#define VIS_MODE_COMPOSITED_COLOR    1
#define VIS_MODE_RESOLVED_COLOR      2
#define VIS_MODE_DIFFUSE             3
#define VIS_MODE_SPECULAR            4
#define VIS_MODE_DENOISED_DIFFUSE    5
#define VIS_MODE_DENOISED_SPECULAR   6
#define VIS_MODE_RESERVOIR_WEIGHT    7
#define VIS_MODE_RESERVOIR_M         8
#define VIS_MODE_DIFFUSE_GRADIENT    9
#define VIS_MODE_SPECULAR_GRADIENT   10
#define VIS_MODE_DIFFUSE_CONFIDENCE  11
#define VIS_MODE_SPECULAR_CONFIDENCE 12
#define VIS_MODE_GI_WEIGHT           13
#define VIS_MODE_GI_M                14

#define VIS_MODE_ENV_VIS_MAP         15
#define VIS_MODE_WS_ENV_VIS_MAP      16
#define VIS_MODE_WS_GRID             17
#define VIS_MODE_ENV_VIS_DEBUG_1     18
#define VIS_MODE_ENV_VIS_DEBUG_2     19

#define BACKGROUND_DEPTH 65504.f

#define RAY_COUNT_TRACED(index) ((index) * 2)
#define RAY_COUNT_HITS(index) ((index) * 2 + 1)

#define REPORT_RAY(hit) if (g_PerPassConstants.rayCountBufferIndex >= 0) { \
    InterlockedAdd(u_RayCountBuffer[RAY_COUNT_TRACED(g_PerPassConstants.rayCountBufferIndex)], 1); \
    if (hit) InterlockedAdd(u_RayCountBuffer[RAY_COUNT_HITS(g_PerPassConstants.rayCountBufferIndex)], 1); }

struct GridParameters
{
    float3 cameraPosition;
    float logarithmBase;
    float3 cameraPositionPrev;
    float sceneScale;
};

struct BrdfRayTracingConstants
{
    PlanarViewConstants view;

    uint frameIndex;
};

struct PrepareLightsConstants
{
    uint numTasks;
    uint currentFrameLightOffset;
    uint previousFrameLightOffset;
};

struct PrepareLightsTask
{
    uint instanceAndGeometryIndex; // low 12 bits are geometryIndex, mid 19 bits are instanceIndex, high bit is TASK_PRIMITIVE_LIGHT_BIT
    uint triangleCount;
    uint lightBufferOffset;
    int previousLightBufferOffset; // -1 means no previous data
};

struct RenderEnvironmentMapConstants
{
    ProceduralSkyShaderParameters params;

    float2 invTextureSize;
};

struct PreprocessEnvironmentMapConstants
{
    uint2 sourceSize;
    uint sourceMipLevel;
    uint numDestMipLevels;
};

struct GBufferConstants
{
    PlanarViewConstants view;
    PlanarViewConstants viewPrev;

    float roughnessOverride;
    float metalnessOverride;
    float normalMapScale;
    uint enableAlphaTestedGeometry;

    int2 materialReadbackPosition;
    uint materialReadbackBufferIndex;
    uint enableTransparentGeometry;

    float textureLodBias;
    float textureGradientScale; // 2^textureLodBias
};

struct GlassConstants
{
    PlanarViewConstants view;
    
    uint enableEnvironmentMap;
    uint environmentMapTextureIndex;
    float environmentScale;
    float environmentRotation;

    int2 materialReadbackPosition;
    uint materialReadbackBufferIndex;
    float normalMapScale;
};

struct CompositingConstants
{
    PlanarViewConstants view;
    PlanarViewConstants viewPrev;

    uint enableTextures;
    uint denoiserMode;
    uint enableEnvironmentMap;
    uint environmentMapTextureIndex;

    float environmentScale;
    float environmentRotation;
    float noiseMix;
    float noiseClampLow;

    float noiseClampHigh;
    uint checkerboard;
};

struct AccumulationConstants
{
    float2 outputSize;
    float2 inputSize;
    float2 inputTextureSizeInv;
    float2 pixelOffset;
    float blendFactor;
};

struct FilterGradientsConstants
{
    uint2 viewportSize;
    int passIndex;
    uint checkerboard;
};

struct ConfidenceConstants
{
    uint2 viewportSize;
    float2 invGradientTextureSize;

    float darknessBias;
    float sensitivity;
    uint checkerboard;
    int inputBufferIndex;

    float blendFactor;
};

struct VisualizationConstants
{
    RTXDI_RuntimeParameters runtimeParams;
    RTXDI_ReservoirBufferParameters restirDIReservoirBufferParams;
    RTXDI_ReservoirBufferParameters restirGIReservoirBufferParams;

    int2 outputSize;
    float2 resolutionScale;

    uint visualizationMode;
    uint inputBufferIndex;
    uint enableAccumulation;
};

struct SceneConstants
{
    uint enableEnvironmentMap; // Global. Affects BRDFRayTracing's GI code, plus RTXDI, ReGIR, etc.
    uint environmentMapTextureIndex; // Global
    float environmentScale;
    float environmentRotation;

    uint enableAlphaTestedGeometry;
    uint enableTransparentGeometry;
    uint2 pad1;
};

struct ResamplingConstants
{
    PlanarViewConstants view;
    PlanarViewConstants prevView;
    RTXDI_RuntimeParameters runtimeParams;
    
    float4 reblurDiffHitDistParams;
    float4 reblurSpecHitDistParams;

    uint frameIndex;
    uint enablePreviousTLAS;
    uint denoiserMode;
    uint discountNaiveSamples;
    
    uint enableBrdfIndirect;
    uint enableBrdfAdditiveBlend;    
    uint enableAccumulation; // StoreShadingOutput

    float sceneGridScale;

    SceneConstants sceneConstants;

    // Common buffer params
    RTXDI_LightBufferParameters lightBufferParams;
    RTXDI_RISBufferSegmentParameters localLightsRISBufferSegmentParams;
    RTXDI_RISBufferSegmentParameters environmentLightRISBufferSegmentParams;

    // Algo-specific params
    ReSTIRDI_Parameters restirDI;
    ReGIR_Parameters regir;
    ReSTIRGI_Parameters restirGI;
    BRDFPathTracing_Parameters brdfPT;

    uint visualizeRegirCells;
    uint guidingFlag;
    uint worldSpaceReservoirFlag;
    uint pad3;
    
    uint2 environmentPdfTextureSize;
    uint2 localLightPdfTextureSize;
};

struct PerPassConstants
{
    int rayCountBufferIndex;
};

struct SecondaryGBufferData
{
    float3 worldPos;
    uint normal;

    uint2 throughputAndFlags;   // .x = throughput.rg as float16, .y = throughput.b as float16, flags << 16
    uint diffuseAlbedo;         // R11G11B10_UFLOAT
    uint specularAndRoughness;  // R8G8B8A8_Gamma_UFLOAT
    
    float3 emission;
    float pdf;
};

static const uint kSecondaryGBuffer_IsSpecularRay = 1;
static const uint kSecondaryGBuffer_IsDeltaSurface = 2;
static const uint kSecondaryGBuffer_IsEnvironmentMap = 4;

static const uint kPolymorphicLightTypeShift = 24;
static const uint kPolymorphicLightTypeMask = 0xf;
static const uint kPolymorphicLightShapingEnableBit = 1 << 28;
static const uint kPolymorphicLightIesProfileEnableBit = 1 << 29;
static const float kPolymorphicLightMinLog2Radiance = -8.f;
static const float kPolymorphicLightMaxLog2Radiance = 40.f;

#ifdef __cplusplus
enum class PolymorphicLightType
#else
enum PolymorphicLightType
#endif
{
    kSphere = 0,
    kCylinder,
    kDisk,
    kRect,
    kTriangle,
    kDirectional,
    kEnvironment,
    kPoint
};

// Stores shared light information (type) and specific light information
// See PolymorphicLight.hlsli for encoding format
struct PolymorphicLightInfo
{
    // uint4[0]
    float3 center;
    uint colorTypeAndFlags; // RGB8 + uint8 (see the kPolymorphicLight... constants above)

    // uint4[1]
    uint direction1; // oct-encoded
    uint direction2; // oct-encoded
    uint scalars; // 2x float16
    uint logRadiance; // uint16

    // uint4[2] -- optional, contains only shaping data
    uint iesProfileIndex;
    uint primaryAxis; // oct-encoded
    uint cosConeAngleAndSoftness; // 2x float16
    uint padding;
};
\
#define WORLD_GRID_DIMENSION     128
#define WORLD_GRID_SIZE          (WORLD_GRID_DIMENSION * WORLD_GRID_DIMENSION * WORLD_GRID_DIMENSION)

#define ENV_GUID_RESOLUTION          6
#define ENV_GUID_MAX_TEMP_RAY_NUM    1000000
#define ENV_GUIDING_SAMPLE_FRACTION  0.9f

#define GUIDING_FLAG_ENABLE         1
#define GUIDING_FLAG_GUIDE_DI       (1 << 1)
#define GUIDING_FLAG_GUIDE_GI       (1 << 2)
#define GUIDING_FLAG_UPDATE_ENABLE  (1 << 3)
#define GUIDING_FLAG_DI_BRDF_MIS    (1 << 4)
#define GUIDING_FLAG_GI_BRDF_MIS    (1 << 5)

struct EnvGuidingData
{
    float luminance[ENV_GUID_RESOLUTION * ENV_GUID_RESOLUTION];
    float total;
    uint3 pad;
};

struct EnvGuidingStats
{
    uint rayCnt;
    uint offset;
    uint2 pad;
};

struct EnvGuidingGridStats
{
    uint rayCnt;
    uint offset;
    uint2 pad;
};

struct EnvRadianceData
{
    float radianceLuminance;
    float3 dir;
    uint gridId;
    uint3 pad;
};

struct EnvVisibilityVisualizationConstants
{
    PlanarViewConstants view;

    uint visualizationMode;
    float2 resolutionScale;
    float sceneGridScale;

    uint flag;
    uint3 pad;
};

#define WORLD_SPACE_LIGHT_SAMPLES_MAX_NUM                   1000000
#define WORLD_SPACE_UPDATABLE_GRID_PER_FRAME_MAX_NUM        10000
// the number of reservoirs in a grid (not bigger than 32 or 64 is better)
#define WORLD_SPACE_RESERVOIR_NUM_PER_GRID                  32
#define WORLD_SPACE_LIGHT_SAMPLES_PER_RESERVOIR_MAX_NUM     (WORLD_SPACE_RESERVOIR_NUM_PER_GRID * 32)

#define WORLD_SPACE_RESERVOIR_UPDATE_ENABLE     (1)
#define WORLD_SPACE_RESERVOIR_TEMPLORAL_ENABLE  (1 << 1)
#define WORLD_SPACE_RESERVOIR_SPATIAL_ENABLE    (1 << 2)
#define WORLD_SPACE_RESERVOIR_DI_ENABLE         (1 << 3)
#define WORLD_SPACE_RESERVOIR_GI_ENABLE         (1 << 4)
#define WORLD_SPACE_RESERVOIR_UPDATE_PRIMARY    (1 << 5)
#define WORLD_SPACE_RESERVOIR_UPDATE_SECONDARY  (1 << 6)

#define WORLD_SPACE_RESERVOIR_SAMPLE_WITH_JITTER (1 << 7)

struct WSRLightSample
{
    uint gridId;
    uint lightIndex;
    float2 uv;
    float random;
    float targetPdf;
    float invSourcePdf;
    uint pad;
};

struct WSRStats
{
    uint sampleCnt;
    uint offset;
    uint activedGridCnt;
};

struct WSRGridStats
{
    uint sampleCnt;
    uint offset;
};

#define VMF_MAX_DATA_NUM 20

struct vMF
{
    float3 mu;
    float kappa;
    float meanCosine;
    float weightSum;
    uint iterationCnt;
    uint dataCnt;
};

struct vMFData
{
    float3 dir;
    float pdf;
    float radianceLuminance;
    float3 pad;
};

#endif // SHADER_PARAMETERS_H
