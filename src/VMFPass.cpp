#include "VMFPass.h"
#include "RtxdiResources.h"
#include "SampleScene.h"

#include <donut/engine/ShaderFactory.h>
#include <donut/engine/CommonRenderPasses.h>
#include <donut/core/log.h>
#include <nvrhi/utils.h>
#include <rtxdi/ReSTIRDI.h>

#include <algorithm>
#include <utility>

using namespace donut::math;
#include "../shaders/ShaderParameters.h"

using namespace donut::engine;


VMFPass::VMFPass(
    nvrhi::IDevice* device, 
    std::shared_ptr<ShaderFactory> shaderFactory, 
    nvrhi::IBindingLayout* bindlessLayout)
    : m_Device(device)
    , m_BindlessLayout(bindlessLayout)
    , m_ShaderFactory(std::move(shaderFactory))
{
    nvrhi::BindingLayoutDesc bindingLayoutDesc;
    bindingLayoutDesc.visibility = nvrhi::ShaderType::Compute;
    bindingLayoutDesc.bindings = {
        nvrhi::BindingLayoutItem::StructuredBuffer_UAV(0),
        nvrhi::BindingLayoutItem::StructuredBuffer_UAV(1),
    };

    m_BindingLayout = m_Device->createBindingLayout(bindingLayoutDesc);
}

void VMFPass::CreatePipeline()
{
    donut::log::debug("Initializing VMFPass...");

    {
        m_ComputeShader = m_ShaderFactory->CreateShader("app/LightingPasses/VMFUpdate.hlsl", "main", nullptr, nvrhi::ShaderType::Compute);

        nvrhi::ComputePipelineDesc pipelineDesc;
        pipelineDesc.bindingLayouts = { m_BindingLayout, m_BindlessLayout };
        pipelineDesc.CS = m_ComputeShader;
        m_ComputePipeline = m_Device->createComputePipeline(pipelineDesc);
    }

    {
        m_ResetShader = m_ShaderFactory->CreateShader("app/LightingPasses/VMFReset.hlsl", "main", nullptr, nvrhi::ShaderType::Compute);

        nvrhi::ComputePipelineDesc pipelineDesc;
        pipelineDesc.bindingLayouts = { m_BindingLayout, m_BindlessLayout };
        pipelineDesc.CS = m_ResetShader;
        m_ResetPipeline = m_Device->createComputePipeline(pipelineDesc);
    }
}

void VMFPass::CreateBindingSet(RtxdiResources& resources)
{
    nvrhi::BindingSetDesc bindingSetDesc;
    bindingSetDesc.bindings = {
        nvrhi::BindingSetItem::StructuredBuffer_UAV(0, resources.vMFBuffer),
        nvrhi::BindingSetItem::StructuredBuffer_UAV(1, resources.vMFDataBuffer),
    };

    m_BindingSet = m_Device->createBindingSet(bindingSetDesc, m_BindingLayout);

    m_vMFBuffer = resources.vMFBuffer;
    m_vMFDataBuffer = resources.vMFDataBuffer;
}

void VMFPass::ProcessUpdate(nvrhi::ICommandList* commandList)
{
    commandList->beginMarker("VMFUpdate");

    nvrhi::ComputeState state;
    state.bindings = { m_BindingSet };
    state.pipeline = m_ComputePipeline;
    commandList->setComputeState(state);

    nvrhi::utils::BufferUavBarrier(commandList, m_vMFBuffer);

    commandList->dispatch((uint32_t)ceil(ENV_GUID_GRID_CELL_SIZE * 1.f / 32), 1, 1);

    commandList->endMarker();
}

void VMFPass::ResetModel(nvrhi::ICommandList* commandList)
{
    commandList->beginMarker("VMFReset");

    nvrhi::ComputeState state;
    state.bindings = { m_BindingSet };
    state.pipeline = m_ResetPipeline;
    commandList->setComputeState(state);

    nvrhi::utils::BufferUavBarrier(commandList, m_vMFBuffer);

    commandList->dispatch((uint32_t)ceil(ENV_GUID_GRID_CELL_SIZE * 1.f / 32), 1, 1);

    commandList->endMarker();
}