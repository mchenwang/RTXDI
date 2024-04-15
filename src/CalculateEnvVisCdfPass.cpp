#include "CalculateEnvVisCdfPass.h"
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


CalculateEnvVisCdfPass::CalculateEnvVisCdfPass(
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
        nvrhi::BindingLayoutItem::TypedBuffer_UAV(1),
    };

    m_BindingLayout = m_Device->createBindingLayout(bindingLayoutDesc);
}

void CalculateEnvVisCdfPass::CreatePipeline()
{
    donut::log::debug("Initializing CalculateEnvVisCdfPass...");

    {
        m_ComputeShader = m_ShaderFactory->CreateShader("app/LightingPasses/CalcEnvVisCdf.hlsl", "main", nullptr, nvrhi::ShaderType::Compute);

        nvrhi::ComputePipelineDesc pipelineDesc;
        pipelineDesc.bindingLayouts = { m_BindingLayout, m_BindlessLayout };
        pipelineDesc.CS = m_ComputeShader;
        m_ComputePipeline = m_Device->createComputePipeline(pipelineDesc);
    }

    {
        m_ResetShader = m_ShaderFactory->CreateShader("app/LightingPasses/ResetEnvVisMap.hlsl", "main", nullptr, nvrhi::ShaderType::Compute);

        nvrhi::ComputePipelineDesc pipelineDesc;
        pipelineDesc.bindingLayouts = { m_BindingLayout, m_BindlessLayout };
        pipelineDesc.CS = m_ResetShader;
        m_ResetPipeline = m_Device->createComputePipeline(pipelineDesc);
    }
}

void CalculateEnvVisCdfPass::CreateBindingSet(RtxdiResources& resources)
{
    nvrhi::BindingSetDesc bindingSetDesc;
    bindingSetDesc.bindings = {
        nvrhi::BindingSetItem::StructuredBuffer_UAV(0, resources.envVisibilityDataBuffer),
        nvrhi::BindingSetItem::TypedBuffer_UAV(1, resources.envVisibilityCdfBuffer),
    };

    m_BindingSet = m_Device->createBindingSet(bindingSetDesc, m_BindingLayout);
}

void CalculateEnvVisCdfPass::Process(nvrhi::ICommandList* commandList)
{
    commandList->beginMarker("CalcEnvVisCdf");

    nvrhi::ComputeState state;
    state.bindings = { m_BindingSet };
    state.pipeline = m_ComputePipeline;
    commandList->setComputeState(state);

    commandList->dispatch((uint32_t)ceil(ENV_GUID_GRID_CELL_SIZE * 1.f / 32), 1, 1);

    commandList->endMarker();
}

void CalculateEnvVisCdfPass::ResetEnvMap(nvrhi::ICommandList* commandList)
{
    commandList->beginMarker("ResetEnvVisMap");

    nvrhi::ComputeState state;
    state.bindings = { m_BindingSet };
    state.pipeline = m_ResetPipeline;
    commandList->setComputeState(state);

    commandList->dispatch((uint32_t)ceil(ENV_GUID_GRID_CELL_SIZE * 1.f / 32), 1, 1);

    commandList->endMarker();
}