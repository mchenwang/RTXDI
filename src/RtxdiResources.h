/***************************************************************************
 # Copyright (c) 2020-2023, NVIDIA CORPORATION.  All rights reserved.
 #
 # NVIDIA CORPORATION and its licensors retain all intellectual property
 # and proprietary rights in and to this software, related documentation
 # and any modifications thereto.  Any use, reproduction, disclosure or
 # distribution of this software and related documentation without an express
 # license agreement from NVIDIA CORPORATION is strictly prohibited.
 **************************************************************************/

#pragma once

#include <nvrhi/nvrhi.h>

namespace rtxdi
{
    class RISBufferSegmentAllocator;
    class ReSTIRDIContext;
    class ImportanceSamplingContext;
}

class RtxdiResources
{
private:
    bool m_NeighborOffsetsInitialized = false;
    uint32_t m_MaxEmissiveMeshes = 0;
    uint32_t m_MaxEmissiveTriangles = 0;
    uint32_t m_MaxPrimitiveLights = 0;
    uint32_t m_MaxGeometryInstances = 0;

public:
    nvrhi::BufferHandle TaskBuffer;
    nvrhi::BufferHandle PrimitiveLightBuffer;
    nvrhi::BufferHandle LightDataBuffer;
    nvrhi::BufferHandle GeometryInstanceToLightBuffer;
    nvrhi::BufferHandle LightIndexMappingBuffer;
    nvrhi::BufferHandle RisBuffer;
    nvrhi::BufferHandle RisLightDataBuffer;
    nvrhi::BufferHandle NeighborOffsetsBuffer;
    nvrhi::BufferHandle LightReservoirBuffer;
    nvrhi::BufferHandle SecondaryGBuffer;
    nvrhi::TextureHandle EnvironmentPdfTexture;
    nvrhi::TextureHandle LocalLightPdfTexture;
    nvrhi::BufferHandle GIReservoirBuffer;

    nvrhi::BufferHandle envGuidingMap;
    nvrhi::BufferHandle envGuidingStats;
    nvrhi::BufferHandle envRadianceBuffer;
    nvrhi::BufferHandle envRadianceBufferReordered;
    nvrhi::BufferHandle envGuidingGridStatsBuffer;

    nvrhi::BufferHandle vMFBuffer;
    nvrhi::BufferHandle vMFDataBuffer;

    nvrhi::TextureHandle debugTexture1;
    nvrhi::TextureHandle debugTexture2;
    nvrhi::BufferHandle debugBuffer1;

    nvrhi::BufferHandle gridHashMapBuffer;
    nvrhi::BufferHandle gridHashMapLockBuffer;

    RtxdiResources(
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
        uint32_t viewportHeight);

    void InitializeNeighborOffsets(nvrhi::ICommandList* commandList, uint32_t neighborOffsetCount);

    uint32_t GetMaxEmissiveMeshes() const { return m_MaxEmissiveMeshes; }
    uint32_t GetMaxEmissiveTriangles() const { return m_MaxEmissiveTriangles; }
    uint32_t GetMaxPrimitiveLights() const { return m_MaxPrimitiveLights; }
    uint32_t GetMaxGeometryInstances() const { return m_MaxGeometryInstances; }
};
