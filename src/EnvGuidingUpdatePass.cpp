#include "EnvGuidingUpdatePass.h"
#include "RtxdiResources.h"
#include "SampleScene.h"

#include <donut/engine/ShaderFactory.h>
#include <donut/engine/CommonRenderPasses.h>
#include <donut/core/log.h>
#include <nvrhi/utils.h>

#include <algorithm>
#include <utility>

using namespace donut::math;
#include "../shaders/ShaderParameters.h"

using namespace donut::engine;


EnvGuidingUpdatePass::EnvGuidingUpdatePass(
    nvrhi::IDevice* device, 
    std::shared_ptr<ShaderFactory> shaderFactory)
    : m_Device(device)
    , m_ShaderFactory(std::move(shaderFactory))
{
    {
        nvrhi::BindingLayoutDesc bindingLayoutDesc;
        bindingLayoutDesc.visibility = nvrhi::ShaderType::Compute;
        bindingLayoutDesc.bindings = {
            nvrhi::BindingLayoutItem::RawBuffer_SRV(0),
            nvrhi::BindingLayoutItem::RawBuffer_UAV(0),
        };
        m_SetIndirectParamsPass.bindingLayout = m_Device->createBindingLayout(bindingLayoutDesc);
    }
    {
        nvrhi::BindingLayoutDesc bindingLayoutDesc;
        bindingLayoutDesc.visibility = nvrhi::ShaderType::Compute;
        bindingLayoutDesc.bindings = {
            // nvrhi::BindingLayoutItem::PushConstants(0, sizeof(uint32_t)),
            nvrhi::BindingLayoutItem::StructuredBuffer_UAV(0),
            nvrhi::BindingLayoutItem::RawBuffer_UAV(1),
        };
        m_SetGridStatsPass.bindingLayout = m_Device->createBindingLayout(bindingLayoutDesc);
    }
    {
        nvrhi::BindingLayoutDesc bindingLayoutDesc;
        bindingLayoutDesc.visibility = nvrhi::ShaderType::Compute;
        bindingLayoutDesc.bindings = {
            nvrhi::BindingLayoutItem::RawBuffer_SRV(0),
            nvrhi::BindingLayoutItem::StructuredBuffer_SRV(1),
            nvrhi::BindingLayoutItem::StructuredBuffer_UAV(0),
            nvrhi::BindingLayoutItem::StructuredBuffer_UAV(1),
        };
        m_ReorderDataPass.bindingLayout = m_Device->createBindingLayout(bindingLayoutDesc);
    }
    {
        nvrhi::BindingLayoutDesc bindingLayoutDesc;
        bindingLayoutDesc.visibility = nvrhi::ShaderType::Compute;
        bindingLayoutDesc.bindings = {
            nvrhi::BindingLayoutItem::StructuredBuffer_SRV(0),
            nvrhi::BindingLayoutItem::RawBuffer_UAV(0),
            nvrhi::BindingLayoutItem::StructuredBuffer_UAV(1),
            nvrhi::BindingLayoutItem::StructuredBuffer_UAV(2),
        };
        m_UpdateGuidingMapPass.bindingLayout = m_Device->createBindingLayout(bindingLayoutDesc);
    }
    {
        nvrhi::BindingLayoutDesc bindingLayoutDesc;
        bindingLayoutDesc.visibility = nvrhi::ShaderType::Compute;
        bindingLayoutDesc.bindings = {
            nvrhi::BindingLayoutItem::StructuredBuffer_UAV(0),
        };
        m_ResetGuidingMapPass.bindingLayout = m_Device->createBindingLayout(bindingLayoutDesc);
    }

    {
        nvrhi::BufferDesc desc;
        desc.debugName = "EnvGuidingUpdatePass::m_IndirectParamsBuffer";
        desc.initialState = nvrhi::ResourceStates::UnorderedAccess;
        desc.keepInitialState = true;
        desc.canHaveRawViews = true;
        desc.canHaveUAVs = true;
        desc.byteSize = sizeof(uint32_t) * 4;
        m_IndirectParamsBuffer = device->createBuffer(desc);
    }
    
}

void EnvGuidingUpdatePass::CreatePipeline()
{
    donut::log::debug("Initializing EnvGuidingUpdatePass...");

    auto Create = [&](const char* path, nvrhi::ShaderHandle &shader, nvrhi::ComputePipelineHandle &pipeline, nvrhi::BindingLayoutHandle &bindingLayout)
    {
        shader = m_ShaderFactory->CreateShader(path, "main", nullptr, nvrhi::ShaderType::Compute);

        nvrhi::ComputePipelineDesc pipelineDesc;
        pipelineDesc.bindingLayouts = { bindingLayout };
        pipelineDesc.CS = shader;
        pipeline = m_Device->createComputePipeline(pipelineDesc);
    };

    Create("app/LightingPasses/EnvGuiding/SetIndirectParams.hlsl", m_SetIndirectParamsPass.shader, m_SetIndirectParamsPass.pipeline, m_SetIndirectParamsPass.bindingLayout);
    Create("app/LightingPasses/EnvGuiding/SetGridStats.hlsl", m_SetGridStatsPass.shader, m_SetGridStatsPass.pipeline, m_SetGridStatsPass.bindingLayout);
    Create("app/LightingPasses/EnvGuiding/ReorderData.hlsl", m_ReorderDataPass.shader, m_ReorderDataPass.pipeline, m_ReorderDataPass.bindingLayout);
    Create("app/LightingPasses/EnvGuiding/UpdateGuidingMap.hlsl", m_UpdateGuidingMapPass.shader, m_UpdateGuidingMapPass.pipeline, m_UpdateGuidingMapPass.bindingLayout);
    Create("app/LightingPasses/EnvGuiding/ResetGuidingMap.hlsl", m_ResetGuidingMapPass.shader, m_ResetGuidingMapPass.pipeline, m_ResetGuidingMapPass.bindingLayout);
}

void EnvGuidingUpdatePass::CreateBindingSet(RtxdiResources& resources)
{
    {
        nvrhi::BindingSetDesc bindingSetDesc;
        bindingSetDesc.bindings = {
            nvrhi::BindingSetItem::RawBuffer_SRV(0, resources.envGuidingStats),
            nvrhi::BindingSetItem::RawBuffer_UAV(0, m_IndirectParamsBuffer),
        };

        m_SetIndirectParamsPass.bindingSet = m_Device->createBindingSet(bindingSetDesc, m_SetIndirectParamsPass.bindingLayout);
    }
    {
        nvrhi::BindingSetDesc bindingSetDesc;
        bindingSetDesc.bindings = {
            // nvrhi::BindingSetItem::PushConstants(0, sizeof(uint32_t)),
            nvrhi::BindingSetItem::StructuredBuffer_UAV(0, resources.envGuidingGridStatsBuffer),
            nvrhi::BindingSetItem::RawBuffer_UAV(1, resources.envGuidingStats),
        };

        m_SetGridStatsPass.bindingSet = m_Device->createBindingSet(bindingSetDesc, m_SetGridStatsPass.bindingLayout);
    }
    {
        nvrhi::BindingSetDesc bindingSetDesc;
        bindingSetDesc.bindings = {
            nvrhi::BindingSetItem::RawBuffer_SRV(0, resources.envGuidingStats),
            nvrhi::BindingSetItem::StructuredBuffer_SRV(1, resources.envRadianceBuffer),
            nvrhi::BindingSetItem::StructuredBuffer_UAV(0, resources.envGuidingGridStatsBuffer),
            nvrhi::BindingSetItem::StructuredBuffer_UAV(1, resources.envRadianceBufferReordered),
        };

        m_ReorderDataPass.bindingSet = m_Device->createBindingSet(bindingSetDesc, m_ReorderDataPass.bindingLayout);
    }
    {
        nvrhi::BindingSetDesc bindingSetDesc;
        bindingSetDesc.bindings = {
            nvrhi::BindingSetItem::StructuredBuffer_SRV(0, resources.envRadianceBufferReordered),
            nvrhi::BindingSetItem::RawBuffer_UAV(0, resources.envGuidingStats),
            nvrhi::BindingSetItem::StructuredBuffer_UAV(1, resources.envGuidingMap),
            nvrhi::BindingSetItem::StructuredBuffer_UAV(2, resources.envGuidingGridStatsBuffer),
        };

        m_UpdateGuidingMapPass.bindingSet = m_Device->createBindingSet(bindingSetDesc, m_UpdateGuidingMapPass.bindingLayout);
    }
    {
        nvrhi::BindingSetDesc bindingSetDesc;
        bindingSetDesc.bindings = {
            nvrhi::BindingSetItem::StructuredBuffer_UAV(0, resources.envGuidingMap),
        };

        m_ResetGuidingMapPass.bindingSet = m_Device->createBindingSet(bindingSetDesc, m_ResetGuidingMapPass.bindingLayout);
    }
}

void EnvGuidingUpdatePass::Process(nvrhi::ICommandList* commandList)
{
    commandList->beginMarker("EnvGuidingUpdatePass::Process");

    {
        nvrhi::ComputeState state;
        state.bindings = { m_SetIndirectParamsPass.bindingSet };
        state.pipeline = m_SetIndirectParamsPass.pipeline;
        commandList->setComputeState(state);
        commandList->dispatch(1, 1, 1);
    }
    {
        nvrhi::ComputeState state;
        state.bindings = { m_SetGridStatsPass.bindingSet };
        state.pipeline = m_SetGridStatsPass.pipeline;
        commandList->setComputeState(state);
        commandList->dispatch((uint32_t)ceil(ENV_GUID_GRID_CELL_SIZE * 1.f / 64), 1, 1);
    }
    {
        nvrhi::ComputeState state;
        state.bindings = { m_ReorderDataPass.bindingSet };
        state.indirectParams = m_IndirectParamsBuffer.Get();
        state.pipeline = m_ReorderDataPass.pipeline;
        commandList->setComputeState(state);
        commandList->dispatchIndirect(0);
    }
    {
        nvrhi::ComputeState state;
        state.bindings = { m_UpdateGuidingMapPass.bindingSet };
        state.pipeline = m_UpdateGuidingMapPass.pipeline;
        commandList->setComputeState(state);
        commandList->dispatch((uint32_t)ceil(ENV_GUID_GRID_CELL_SIZE * 1.f / 64), 1, 1);
    }
    
    commandList->endMarker();
}

void EnvGuidingUpdatePass::Reset(nvrhi::ICommandList* commandList)
{
    commandList->beginMarker("EnvGuidingUpdatePass::Reset");

    nvrhi::ComputeState state;
    state.bindings = { m_ResetGuidingMapPass.bindingSet };
    state.pipeline = m_ResetGuidingMapPass.pipeline;
    commandList->setComputeState(state);

    commandList->dispatch((uint32_t)ceil(ENV_GUID_GRID_CELL_SIZE * 1.f / 64), 1, 1);

    commandList->endMarker();
}