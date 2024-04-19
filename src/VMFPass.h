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

class VMFPass
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

    nvrhi::BufferHandle m_vMFBuffer;
    nvrhi::BufferHandle m_vMFDataBuffer;
    
    std::shared_ptr<donut::engine::ShaderFactory> m_ShaderFactory;

public:
    VMFPass(
        nvrhi::IDevice* device,
        std::shared_ptr<donut::engine::ShaderFactory> shaderFactory,
        nvrhi::IBindingLayout* bindlessLayout);

    void CreatePipeline();
    void CreateBindingSet(RtxdiResources& resources);
    
    void ProcessUpdate(nvrhi::ICommandList* commandList);
    void ResetModel(nvrhi::ICommandList* commandList);
};
