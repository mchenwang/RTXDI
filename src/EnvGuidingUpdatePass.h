#pragma once

#include <nvrhi/nvrhi.h>
#include <memory>

namespace donut::engine
{
    class ShaderFactory;
}

class RtxdiResources;

class EnvGuidingUpdatePass
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
      m_UpdateGuidingMapPass,
      m_ResetGuidingMapPass;
    
    std::shared_ptr<donut::engine::ShaderFactory> m_ShaderFactory;

    nvrhi::BufferHandle m_IndirectParamsBuffer;

public:
    EnvGuidingUpdatePass(
        nvrhi::IDevice* device,
        std::shared_ptr<donut::engine::ShaderFactory> shaderFactory);

    void CreatePipeline();
    void CreateBindingSet(RtxdiResources& resources);
    
    void Process(nvrhi::ICommandList* commandList);
    void Reset(nvrhi::ICommandList* commandList);
};
