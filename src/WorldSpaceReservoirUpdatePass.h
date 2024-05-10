#pragma once

#include <nvrhi/nvrhi.h>
#include <memory>

namespace donut::engine
{
    class ShaderFactory;
}

class RtxdiResources;

class WorldSpaceReservoirUpdatePass
{
private:
    nvrhi::DeviceHandle m_Device;

    struct
    {
        nvrhi::ShaderHandle shader;
        nvrhi::ComputePipelineHandle pipeline;
        nvrhi::BindingLayoutHandle bindingLayout;
        nvrhi::BindingSetHandle bindingSet;
    } m_SetIndirectParamsPass, 
      m_SetGridStatsPass, 
      m_ReorderDataPass, 
      m_UpdateReservoirPass,
      m_ResetPass;

    nvrhi::BufferHandle m_UpdatableGridQueue;

    nvrhi::IBuffer* m_WorldSpaceReservoirStatsBuffer;
    nvrhi::IBuffer* m_WorldSpaceGridStatsBuffer;
    
    std::shared_ptr<donut::engine::ShaderFactory> m_ShaderFactory;

    nvrhi::BufferHandle m_IndirectParamsBuffer;

public:
    WorldSpaceReservoirUpdatePass(
        nvrhi::IDevice* device,
        std::shared_ptr<donut::engine::ShaderFactory> shaderFactory);

    void CreatePipeline();
    void CreateBindingSet(RtxdiResources& resources);
    
    void Process(nvrhi::ICommandList* commandList);
    void Reset(nvrhi::ICommandList* commandList);
};
