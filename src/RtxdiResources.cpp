/***************************************************************************
 # Copyright (c) 2020-2023, NVIDIA CORPORATION.  All rights reserved.
 #
 # NVIDIA CORPORATION and its licensors retain all intellectual property
 # and proprietary rights in and to this software, related documentation
 # and any modifications thereto.  Any use, reproduction, disclosure or
 # distribution of this software and related documentation without an express
 # license agreement from NVIDIA CORPORATION is strictly prohibited.
 **************************************************************************/

#include "RtxdiResources.h"
#include <rtxdi/ReSTIRDI.h>
#include <rtxdi/ReSTIRGI.h>
#include <rtxdi/RISBufferSegmentAllocator.h>

#include <donut/core/math/math.h>

using namespace dm;
#include "../shaders/ShaderParameters.h"

RtxdiResources::RtxdiResources(
    nvrhi::IDevice* device, 
    const rtxdi::ReSTIRDIContext& context,
    const rtxdi::RISBufferSegmentAllocator& risBufferSegmentAllocator,
    uint32_t maxEmissiveMeshes,
    uint32_t maxEmissiveTriangles,
    uint32_t maxPrimitiveLights,
    uint32_t maxGeometryInstances,
    uint32_t environmentMapWidth,
    uint32_t environmentMapHeight,
    uint32_t viewportWidth,
    uint32_t viewportHeight)
    : m_MaxEmissiveMeshes(maxEmissiveMeshes)
    , m_MaxEmissiveTriangles(maxEmissiveTriangles)
    , m_MaxPrimitiveLights(maxPrimitiveLights)
    , m_MaxGeometryInstances(maxGeometryInstances)
{
    nvrhi::BufferDesc taskBufferDesc;
    taskBufferDesc.byteSize = sizeof(PrepareLightsTask) * (maxEmissiveMeshes + maxPrimitiveLights);
    taskBufferDesc.structStride = sizeof(PrepareLightsTask);
    taskBufferDesc.initialState = nvrhi::ResourceStates::ShaderResource;
    taskBufferDesc.keepInitialState = true;
    taskBufferDesc.debugName = "TaskBuffer";
    taskBufferDesc.canHaveUAVs = true;
    TaskBuffer = device->createBuffer(taskBufferDesc);


    nvrhi::BufferDesc primitiveLightBufferDesc;
    primitiveLightBufferDesc.byteSize = sizeof(PolymorphicLightInfo) * maxPrimitiveLights;
    primitiveLightBufferDesc.structStride = sizeof(PolymorphicLightInfo);
    primitiveLightBufferDesc.initialState = nvrhi::ResourceStates::ShaderResource;
    primitiveLightBufferDesc.keepInitialState = true;
    primitiveLightBufferDesc.debugName = "PrimitiveLightBuffer";
    PrimitiveLightBuffer = device->createBuffer(primitiveLightBufferDesc);


    nvrhi::BufferDesc risBufferDesc;
    risBufferDesc.byteSize = sizeof(uint32_t) * 2 * std::max(risBufferSegmentAllocator.getTotalSizeInElements(), 1u); // RG32_UINT per element
    risBufferDesc.format = nvrhi::Format::RG32_UINT;
    risBufferDesc.canHaveTypedViews = true;
    risBufferDesc.initialState = nvrhi::ResourceStates::ShaderResource;
    risBufferDesc.keepInitialState = true;
    risBufferDesc.debugName = "RisBuffer";
    risBufferDesc.canHaveUAVs = true;
    RisBuffer = device->createBuffer(risBufferDesc);


    risBufferDesc.byteSize = sizeof(uint32_t) * 8 * std::max(risBufferSegmentAllocator.getTotalSizeInElements(), 1u); // RGBA32_UINT x 2 per element
    risBufferDesc.format = nvrhi::Format::RGBA32_UINT;
    risBufferDesc.debugName = "RisLightDataBuffer";
    RisLightDataBuffer = device->createBuffer(risBufferDesc);


    uint32_t maxLocalLights = maxEmissiveTriangles + maxPrimitiveLights;
    uint32_t lightBufferElements = maxLocalLights * 2;

    nvrhi::BufferDesc lightBufferDesc;
    lightBufferDesc.byteSize = sizeof(PolymorphicLightInfo) * lightBufferElements;
    lightBufferDesc.structStride = sizeof(PolymorphicLightInfo);
    lightBufferDesc.initialState = nvrhi::ResourceStates::ShaderResource;
    lightBufferDesc.keepInitialState = true;
    lightBufferDesc.debugName = "LightDataBuffer";
    lightBufferDesc.canHaveUAVs = true;
    LightDataBuffer = device->createBuffer(lightBufferDesc);


    nvrhi::BufferDesc geometryInstanceToLightBufferDesc;
    geometryInstanceToLightBufferDesc.byteSize = sizeof(uint32_t) * maxGeometryInstances;
    geometryInstanceToLightBufferDesc.structStride = sizeof(uint32_t);
    geometryInstanceToLightBufferDesc.initialState = nvrhi::ResourceStates::ShaderResource;
    geometryInstanceToLightBufferDesc.keepInitialState = true;
    geometryInstanceToLightBufferDesc.debugName = "GeometryInstanceToLightBuffer";
    GeometryInstanceToLightBuffer = device->createBuffer(geometryInstanceToLightBufferDesc);


    nvrhi::BufferDesc lightIndexMappingBufferDesc;
    lightIndexMappingBufferDesc.byteSize = sizeof(uint32_t) * lightBufferElements;
    lightIndexMappingBufferDesc.format = nvrhi::Format::R32_UINT;
    lightIndexMappingBufferDesc.canHaveTypedViews = true;
    lightIndexMappingBufferDesc.initialState = nvrhi::ResourceStates::ShaderResource;
    lightIndexMappingBufferDesc.keepInitialState = true;
    lightIndexMappingBufferDesc.debugName = "LightIndexMappingBuffer";
    lightIndexMappingBufferDesc.canHaveUAVs = true;
    LightIndexMappingBuffer = device->createBuffer(lightIndexMappingBufferDesc);
    

    nvrhi::BufferDesc neighborOffsetBufferDesc;
    neighborOffsetBufferDesc.byteSize = context.getStaticParameters().NeighborOffsetCount * 2;
    neighborOffsetBufferDesc.format = nvrhi::Format::RG8_SNORM;
    neighborOffsetBufferDesc.canHaveTypedViews = true;
    neighborOffsetBufferDesc.debugName = "NeighborOffsets";
    neighborOffsetBufferDesc.initialState = nvrhi::ResourceStates::ShaderResource;
    neighborOffsetBufferDesc.keepInitialState = true;
    NeighborOffsetsBuffer = device->createBuffer(neighborOffsetBufferDesc);


    nvrhi::BufferDesc lightReservoirBufferDesc;
    lightReservoirBufferDesc.byteSize = sizeof(RTXDI_PackedDIReservoir) * context.getReservoirBufferParameters().reservoirArrayPitch * rtxdi::c_NumReSTIRDIReservoirBuffers;
    lightReservoirBufferDesc.structStride = sizeof(RTXDI_PackedDIReservoir);
    lightReservoirBufferDesc.initialState = nvrhi::ResourceStates::UnorderedAccess;
    lightReservoirBufferDesc.keepInitialState = true;
    lightReservoirBufferDesc.debugName = "LightReservoirBuffer";
    lightReservoirBufferDesc.canHaveUAVs = true;
    LightReservoirBuffer = device->createBuffer(lightReservoirBufferDesc);


    nvrhi::BufferDesc secondaryGBufferDesc;
    secondaryGBufferDesc.byteSize = sizeof(SecondaryGBufferData) * context.getReservoirBufferParameters().reservoirArrayPitch;
    secondaryGBufferDesc.structStride = sizeof(SecondaryGBufferData);
    secondaryGBufferDesc.initialState = nvrhi::ResourceStates::UnorderedAccess;
    secondaryGBufferDesc.keepInitialState = true;
    secondaryGBufferDesc.debugName = "SecondaryGBuffer";
    secondaryGBufferDesc.canHaveUAVs = true;
    SecondaryGBuffer = device->createBuffer(secondaryGBufferDesc);


    nvrhi::TextureDesc environmentPdfDesc;
    environmentPdfDesc.width = environmentMapWidth;
    environmentPdfDesc.height = environmentMapHeight;
    environmentPdfDesc.mipLevels = uint32_t(ceilf(::log2f(float(std::max(environmentPdfDesc.width, environmentPdfDesc.height)))) + 1); // full mip chain up to 1x1
    environmentPdfDesc.isUAV = true;
    environmentPdfDesc.debugName = "EnvironmentPdf";
    environmentPdfDesc.initialState = nvrhi::ResourceStates::ShaderResource;
    environmentPdfDesc.keepInitialState = true;
    environmentPdfDesc.format = nvrhi::Format::R16_FLOAT;
    EnvironmentPdfTexture = device->createTexture(environmentPdfDesc);

    nvrhi::TextureDesc localLightPdfDesc;
    rtxdi::ComputePdfTextureSize(maxLocalLights, localLightPdfDesc.width, localLightPdfDesc.height, localLightPdfDesc.mipLevels);
    assert(localLightPdfDesc.width * localLightPdfDesc.height >= maxLocalLights);
    localLightPdfDesc.isUAV = true;
    localLightPdfDesc.debugName = "LocalLightPdf";
    localLightPdfDesc.initialState = nvrhi::ResourceStates::ShaderResource;
    localLightPdfDesc.keepInitialState = true;
    localLightPdfDesc.format = nvrhi::Format::R32_FLOAT; // Use FP32 here to allow a wide range of flux values, esp. when downsampled.
    LocalLightPdfTexture = device->createTexture(localLightPdfDesc);
    
    nvrhi::BufferDesc giReservoirBufferDesc;
    giReservoirBufferDesc.byteSize = sizeof(RTXDI_PackedGIReservoir) * context.getReservoirBufferParameters().reservoirArrayPitch * rtxdi::c_NumReSTIRGIReservoirBuffers;
    giReservoirBufferDesc.structStride = sizeof(RTXDI_PackedGIReservoir);
    giReservoirBufferDesc.initialState = nvrhi::ResourceStates::UnorderedAccess;
    giReservoirBufferDesc.keepInitialState = true;
    giReservoirBufferDesc.debugName = "GIReservoirBuffer";
    giReservoirBufferDesc.canHaveUAVs = true;
    GIReservoirBuffer = device->createBuffer(giReservoirBufferDesc);

    nvrhi::TextureDesc debugTexture1Desc;
    debugTexture1Desc.width = viewportWidth;
    debugTexture1Desc.height = viewportHeight;
    debugTexture1Desc.initialState = nvrhi::ResourceStates::ShaderResource;
    debugTexture1Desc.debugName = "debugTexture1";
    debugTexture1Desc.keepInitialState = true;
    debugTexture1Desc.isUAV = true;
    debugTexture1Desc.format = nvrhi::Format::RGBA32_FLOAT;
    debugTexture1 = device->createTexture(debugTexture1Desc);

    nvrhi::TextureDesc debugTexture2Desc;
    debugTexture2Desc.width = viewportWidth;
    debugTexture2Desc.height = viewportHeight;
    debugTexture2Desc.initialState = nvrhi::ResourceStates::ShaderResource;
    debugTexture2Desc.debugName = "debugTexture2";
    debugTexture2Desc.keepInitialState = true;
    debugTexture2Desc.isUAV = true;
    debugTexture2Desc.format = nvrhi::Format::RGBA32_FLOAT;
    debugTexture2 = device->createTexture(debugTexture2Desc);

    {
        nvrhi::BufferDesc desc;
        desc.byteSize = sizeof(uint32_t) * WORLD_GRID_SIZE;
        desc.structStride = sizeof(uint32_t);
        desc.initialState = nvrhi::ResourceStates::UnorderedAccess;
        desc.keepInitialState = true;
        desc.debugName = "gridHashMapBuffer";
        desc.canHaveUAVs = true;
        gridHashMapBuffer = device->createBuffer(desc);
    }

    {
        {
            nvrhi::BufferDesc desc;
            desc.byteSize = sizeof(WSRSurfaceData) * WORLD_GRID_SIZE * WORLD_SPACE_RESERVOIR_NUM_PER_GRID * 2;
            desc.structStride = sizeof(WSRSurfaceData);
            desc.initialState = nvrhi::ResourceStates::ShaderResource;
            desc.keepInitialState = true;
            desc.debugName = "worldSpaceReservoirSurfaceBuffer";
            desc.canHaveUAVs = true;
            worldSpaceReservoirSurfaceBuffer = device->createBuffer(desc);
        }
        {
            nvrhi::BufferDesc desc;
            desc.byteSize = sizeof(WorldSpaceDIReservoir) * WORLD_GRID_SIZE * WORLD_SPACE_RESERVOIR_NUM_PER_GRID * 2;
            desc.structStride = sizeof(WorldSpaceDIReservoir);
            desc.initialState = nvrhi::ResourceStates::ShaderResource;
            desc.keepInitialState = true;
            desc.debugName = "worldSpaceLightReservoirsBuffer";
            desc.canHaveUAVs = true;
            worldSpaceLightReservoirsBuffer = device->createBuffer(desc);
        }
        {
            nvrhi::BufferDesc desc;
            desc.debugName = "worldSpaceReservoirsStats";
            desc.initialState = nvrhi::ResourceStates::UnorderedAccess;
            desc.keepInitialState = true;
            desc.canHaveRawViews = true;
            desc.canHaveUAVs = true;
            desc.byteSize = sizeof(WSRStats);
            worldSpaceReservoirsStats = device->createBuffer(desc);
        }
        {
            nvrhi::BufferDesc desc;
            desc.byteSize = sizeof(WSRLightSample) * WORLD_SPACE_LIGHT_SAMPLES_MAX_NUM;
            desc.structStride = sizeof(WSRLightSample);
            desc.initialState = nvrhi::ResourceStates::UnorderedAccess;
            desc.keepInitialState = true;
            desc.debugName = "worldSpaceLightSamplesBuffer";
            desc.canHaveUAVs = true;
            worldSpaceLightSamplesBuffer = device->createBuffer(desc);

            desc.debugName = "worldSpaceReorderedLightSamplesBuffer";
            worldSpaceReorderedLightSamplesBuffer = device->createBuffer(desc);
        }
        {
            nvrhi::BufferDesc desc;
            desc.byteSize = sizeof(WSRGridStats) * WORLD_GRID_SIZE;
            desc.structStride = sizeof(WSRGridStats);
            desc.initialState = nvrhi::ResourceStates::UnorderedAccess;
            desc.keepInitialState = true;
            desc.debugName = "worldSpaceGridStatsBuffer";
            desc.canHaveUAVs = true;
            worldSpaceGridStatsBuffer = device->createBuffer(desc);
        }
        {
            nvrhi::BufferDesc desc;
            desc.byteSize = sizeof(WSRCellDataInGrid) * WORLD_GRID_SIZE * 2;
            desc.structStride = sizeof(WSRCellDataInGrid);
            desc.initialState = nvrhi::ResourceStates::UnorderedAccess;
            desc.keepInitialState = true;
            desc.debugName = "worldSpaceCellStatsBuffer";
            desc.canHaveUAVs = true;
            worldSpaceCellStatsBuffer = device->createBuffer(desc);
        }
    }
}

void RtxdiResources::InitializeNeighborOffsets(nvrhi::ICommandList* commandList, uint32_t neighborOffsetCount)
{
    if (m_NeighborOffsetsInitialized)
        return;

    std::vector<uint8_t> offsets;
    offsets.resize(neighborOffsetCount * 2);

    rtxdi::FillNeighborOffsetBuffer(offsets.data(), neighborOffsetCount);

    commandList->writeBuffer(NeighborOffsetsBuffer, offsets.data(), offsets.size());

    m_NeighborOffsetsInitialized = true;
}
