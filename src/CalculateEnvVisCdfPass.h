#pragma once

#include <donut/engine/SceneGraph.h>
#include <nvrhi/nvrhi.h>
#include <rtxdi/ReSTIRDI.h>
#include <memory>
#include <unordered_map>


namespace donut::engine
{
    class CommonRenderPasses;
    class ShaderFactory;
    class Scene;
    class Light;
}

class RtxdiResources;

class CalculateEnvVisCdfPass
{
private:
    nvrhi::DeviceHandle m_Device;

    nvrhi::ShaderHandle m_ComputeShader;
    nvrhi::ComputePipelineHandle m_ComputePipeline;
    nvrhi::ShaderHandle m_ResetShader;
    nvrhi::ComputePipelineHandle m_ResetPipeline;
    nvrhi::BindingLayoutHandle m_BindingLayout;
    nvrhi::BindingSetHandle m_BindingSet;
    nvrhi::BindingLayoutHandle m_BindlessLayout;
    
    std::shared_ptr<donut::engine::ShaderFactory> m_ShaderFactory;

public:
    CalculateEnvVisCdfPass(
        nvrhi::IDevice* device,
        std::shared_ptr<donut::engine::ShaderFactory> shaderFactory,
        nvrhi::IBindingLayout* bindlessLayout);

    void CreatePipeline();
    void CreateBindingSet(RtxdiResources& resources);
    
    void Process(nvrhi::ICommandList* commandList);
    void ResetEnvMap(nvrhi::ICommandList* commandList);
};
