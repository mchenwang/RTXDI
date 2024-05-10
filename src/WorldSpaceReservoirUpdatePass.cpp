#include "WorldSpaceReservoirUpdatePass.h"
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


WorldSpaceReservoirUpdatePass::WorldSpaceReservoirUpdatePass(
    nvrhi::IDevice* device, 
    std::shared_ptr<ShaderFactory> shaderFactory)
    : m_Device(device)
    , m_ShaderFactory(std::move(shaderFactory))
{
    {
        nvrhi::BindingLayoutDesc bindingLayoutDesc;
        bindingLayoutDesc.visibility = nvrhi::ShaderType::Compute;
        bindingLayoutDesc.bindings = {
            nvrhi::BindingLayoutItem::RawBuffer_UAV(0),
            nvrhi::BindingLayoutItem::RawBuffer_UAV(1),
        };
        m_SetIndirectParamsPass.bindingLayout = m_Device->createBindingLayout(bindingLayoutDesc);
    }
    {
        nvrhi::BindingLayoutDesc bindingLayoutDesc;
        bindingLayoutDesc.visibility = nvrhi::ShaderType::Compute;
        bindingLayoutDesc.bindings = {
            nvrhi::BindingLayoutItem::StructuredBuffer_UAV(0),
            nvrhi::BindingLayoutItem::RawBuffer_UAV(1),
            nvrhi::BindingLayoutItem::TypedBuffer_UAV(2),
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
            nvrhi::BindingLayoutItem::RawBuffer_SRV(1),
            nvrhi::BindingLayoutItem::StructuredBuffer_UAV(0),
            nvrhi::BindingLayoutItem::StructuredBuffer_UAV(1),
            nvrhi::BindingLayoutItem::TypedBuffer_SRV(2),
        };
        m_UpdateReservoirPass.bindingLayout = m_Device->createBindingLayout(bindingLayoutDesc);
    }
    {
        nvrhi::BindingLayoutDesc bindingLayoutDesc;
        bindingLayoutDesc.visibility = nvrhi::ShaderType::Compute;
        bindingLayoutDesc.bindings = {
            nvrhi::BindingLayoutItem::StructuredBuffer_UAV(0),
        };
        m_ResetPass.bindingLayout = m_Device->createBindingLayout(bindingLayoutDesc);
    }

    {
        nvrhi::BufferDesc desc;
        desc.debugName = "WorldSpaceReservoirUpdatePass::m_IndirectParamsBuffer";
        desc.initialState = nvrhi::ResourceStates::UnorderedAccess;
        desc.keepInitialState = true;
        desc.canHaveRawViews = true;
        desc.canHaveUAVs = true;
        desc.byteSize = sizeof(uint32_t) * 4 * 2;
        m_IndirectParamsBuffer = device->createBuffer(desc);
    }

    {
        nvrhi::BufferDesc desc;
        desc.byteSize = sizeof(uint32_t) * WORLD_SPACE_UPDATABLE_GRID_PER_FRAME_MAX_NUM;
        desc.structStride = sizeof(uint32_t);
        desc.format = nvrhi::Format::R32_UINT;
        desc.initialState = nvrhi::ResourceStates::UnorderedAccess;
        desc.keepInitialState = true;
        desc.debugName = "m_UpdatableGridQueue";
        desc.canHaveUAVs = true;
        m_UpdatableGridQueue = device->createBuffer(desc);
    }
    
}

void WorldSpaceReservoirUpdatePass::CreatePipeline()
{
    donut::log::debug("Initializing WorldSpaceReservoirUpdatePass...");

    auto Create = [&](const char* path, nvrhi::ShaderHandle &shader, nvrhi::ComputePipelineHandle &pipeline, nvrhi::BindingLayoutHandle &bindingLayout)
    {
        shader = m_ShaderFactory->CreateShader(path, "main", nullptr, nvrhi::ShaderType::Compute);

        nvrhi::ComputePipelineDesc pipelineDesc;
        pipelineDesc.bindingLayouts = { bindingLayout };
        pipelineDesc.CS = shader;
        pipeline = m_Device->createComputePipeline(pipelineDesc);
    };

    Create("app/LightingPasses/WSR/SetIndirectParams.hlsl", m_SetIndirectParamsPass.shader, m_SetIndirectParamsPass.pipeline, m_SetIndirectParamsPass.bindingLayout);
    Create("app/LightingPasses/WSR/SetGridStats.hlsl", m_SetGridStatsPass.shader, m_SetGridStatsPass.pipeline, m_SetGridStatsPass.bindingLayout);
    Create("app/LightingPasses/WSR/ReorderData.hlsl", m_ReorderDataPass.shader, m_ReorderDataPass.pipeline, m_ReorderDataPass.bindingLayout);
    Create("app/LightingPasses/WSR/UpdateReservoir.hlsl", m_UpdateReservoirPass.shader, m_UpdateReservoirPass.pipeline, m_UpdateReservoirPass.bindingLayout);
    Create("app/LightingPasses/WSR/ResetReservoir.hlsl", m_ResetPass.shader, m_ResetPass.pipeline, m_ResetPass.bindingLayout);
}

void WorldSpaceReservoirUpdatePass::CreateBindingSet(RtxdiResources& resources)
{
    m_WorldSpaceReservoirStatsBuffer = resources.worldSpaceReservoirsStats.Get();
    m_WorldSpaceGridStatsBuffer = resources.worldSpaceGridStatsBuffer.Get();

    {
        nvrhi::BindingSetDesc bindingSetDesc;
        bindingSetDesc.bindings = {
            nvrhi::BindingSetItem::RawBuffer_UAV(0, m_IndirectParamsBuffer),
            nvrhi::BindingSetItem::RawBuffer_UAV(1, resources.worldSpaceReservoirsStats),
        };

        m_SetIndirectParamsPass.bindingSet = m_Device->createBindingSet(bindingSetDesc, m_SetIndirectParamsPass.bindingLayout);
    }
    {
        nvrhi::BindingSetDesc bindingSetDesc;
        bindingSetDesc.bindings = {
            nvrhi::BindingSetItem::StructuredBuffer_UAV(0, resources.worldSpaceGridStatsBuffer),
            nvrhi::BindingSetItem::RawBuffer_UAV(1, resources.worldSpaceReservoirsStats),
            nvrhi::BindingSetItem::TypedBuffer_UAV(2, m_UpdatableGridQueue),
        };

        m_SetGridStatsPass.bindingSet = m_Device->createBindingSet(bindingSetDesc, m_SetGridStatsPass.bindingLayout);
    }
    {
        nvrhi::BindingSetDesc bindingSetDesc;
        bindingSetDesc.bindings = {
            nvrhi::BindingSetItem::RawBuffer_SRV(0, resources.worldSpaceReservoirsStats),
            nvrhi::BindingSetItem::StructuredBuffer_SRV(1, resources.worldSpaceLightSamplesBuffer),
            nvrhi::BindingSetItem::StructuredBuffer_UAV(0, resources.worldSpaceGridStatsBuffer),
            nvrhi::BindingSetItem::StructuredBuffer_UAV(1, resources.worldSpaceReorderedLightSamplesBuffer),
        };

        m_ReorderDataPass.bindingSet = m_Device->createBindingSet(bindingSetDesc, m_ReorderDataPass.bindingLayout);
    }
    {
        nvrhi::BindingSetDesc bindingSetDesc;
        bindingSetDesc.bindings = {
            nvrhi::BindingSetItem::StructuredBuffer_SRV(0, resources.worldSpaceReorderedLightSamplesBuffer),
            nvrhi::BindingSetItem::RawBuffer_SRV(1, m_IndirectParamsBuffer),
            nvrhi::BindingSetItem::StructuredBuffer_UAV(0, resources.worldSpaceLightReservoirsBuffer),
            nvrhi::BindingSetItem::StructuredBuffer_UAV(1, resources.worldSpaceGridStatsBuffer),
            nvrhi::BindingSetItem::TypedBuffer_SRV(2, m_UpdatableGridQueue),
        };

        m_UpdateReservoirPass.bindingSet = m_Device->createBindingSet(bindingSetDesc, m_UpdateReservoirPass.bindingLayout);
    }
    {
        nvrhi::BindingSetDesc bindingSetDesc;
        bindingSetDesc.bindings = {
            nvrhi::BindingSetItem::StructuredBuffer_UAV(0, resources.worldSpaceLightReservoirsBuffer),
        };

        m_ResetPass.bindingSet = m_Device->createBindingSet(bindingSetDesc, m_ResetPass.bindingLayout);
    }
}

void WorldSpaceReservoirUpdatePass::Process(nvrhi::ICommandList* commandList)
{
    commandList->beginMarker("WorldSpaceReservoirUpdatePass::Process");

    {
        nvrhi::ComputeState state;
        state.bindings = { m_SetGridStatsPass.bindingSet };
        state.pipeline = m_SetGridStatsPass.pipeline;
        commandList->setComputeState(state);
        commandList->dispatch((uint32_t)ceil(WORLD_GRID_SIZE * 1.f / 64), 1, 1);
    }
    {
        nvrhi::ComputeState state;
        state.bindings = { m_SetIndirectParamsPass.bindingSet };
        state.pipeline = m_SetIndirectParamsPass.pipeline;
        commandList->setComputeState(state);
        commandList->dispatch(1, 1, 1);
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
        state.bindings = { m_UpdateReservoirPass.bindingSet };
        state.indirectParams = m_IndirectParamsBuffer.Get();
        state.pipeline = m_UpdateReservoirPass.pipeline;
        commandList->setComputeState(state);
        commandList->dispatchIndirect(16);
        // commandList->dispatch((uint32_t)ceil(WORLD_GRID_SIZE * 1.f / 64), 1, 1);
    }

    commandList->clearBufferUInt(m_WorldSpaceReservoirStatsBuffer, 0);
    commandList->clearBufferUInt(m_WorldSpaceGridStatsBuffer, 0);
    
    commandList->endMarker();
}

void WorldSpaceReservoirUpdatePass::Reset(nvrhi::ICommandList* commandList)
{
    commandList->beginMarker("WorldSpaceReservoirUpdatePass::Reset");

    nvrhi::ComputeState state;
    state.bindings = { m_ResetPass.bindingSet };
    state.pipeline = m_ResetPass.pipeline;
    commandList->setComputeState(state);

    commandList->dispatch((uint32_t)ceil(WORLD_GRID_SIZE * 1.f / 64), 1, 1);

    commandList->endMarker();
}