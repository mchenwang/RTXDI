/***************************************************************************
 # Copyright (c) 2021-2023, NVIDIA CORPORATION.  All rights reserved.
 #
 # NVIDIA CORPORATION and its licensors retain all intellectual property
 # and proprietary rights in and to this software, related documentation
 # and any modifications thereto.  Any use, reproduction, disclosure or
 # distribution of this software and related documentation without an express
 # license agreement from NVIDIA CORPORATION is strictly prohibited.
 **************************************************************************/

#include "VisualizationPass.h"

#include <donut/engine/CommonRenderPasses.h>
#include <donut/engine/ShaderFactory.h>
#include <donut/engine/View.h>
#include <nvrhi/utils.h>
#include <rtxdi/ImportanceSamplingContext.h>

#include "RenderTargets.h"
#include "RtxdiResources.h"

using namespace donut::math;
#include "../shaders/ShaderParameters.h"

using namespace donut::engine;

VisualizationPass::VisualizationPass(nvrhi::IDevice* device,
    CommonRenderPasses& commonPasses,
    ShaderFactory& shaderFactory,
    RenderTargets& renderTargets,
    RtxdiResources& rtxdiResources)
    : m_Device(device)
{
    m_VertexShader = commonPasses.m_FullscreenVS;
    m_HdrPixelShader = shaderFactory.CreateShader("app/VisualizeHdrSignals.hlsl", "main", nullptr, nvrhi::ShaderType::Pixel);
    m_ConfidencePixelShader = shaderFactory.CreateShader("app/VisualizeConfidence.hlsl", "main", nullptr, nvrhi::ShaderType::Pixel);

    auto constantBufferDesc = nvrhi::utils::CreateVolatileConstantBufferDesc(sizeof(VisualizationConstants), "VisualizationConstants", 16);

    m_ConstantBuffer = device->createBuffer(constantBufferDesc);

    auto bindingDesc = nvrhi::BindingSetDesc()
        .addItem(nvrhi::BindingSetItem::Texture_SRV(0, renderTargets.HdrColor))
        .addItem(nvrhi::BindingSetItem::Texture_SRV(1, renderTargets.ResolvedColor))
        .addItem(nvrhi::BindingSetItem::Texture_SRV(2, renderTargets.AccumulatedColor))
        .addItem(nvrhi::BindingSetItem::Texture_SRV(3, renderTargets.DiffuseLighting))
        .addItem(nvrhi::BindingSetItem::Texture_SRV(4, renderTargets.SpecularLighting))
        .addItem(nvrhi::BindingSetItem::Texture_SRV(5, renderTargets.DenoisedDiffuseLighting))
        .addItem(nvrhi::BindingSetItem::Texture_SRV(6, renderTargets.DenoisedSpecularLighting))
        .addItem(nvrhi::BindingSetItem::Texture_SRV(7, renderTargets.Gradients))
        .addItem(nvrhi::BindingSetItem::StructuredBuffer_SRV(8, rtxdiResources.LightReservoirBuffer))
        .addItem(nvrhi::BindingSetItem::StructuredBuffer_SRV(9, rtxdiResources.GIReservoirBuffer))
        .addItem(nvrhi::BindingSetItem::ConstantBuffer(0, m_ConstantBuffer));

    nvrhi::utils::CreateBindingSetAndLayout(device, nvrhi::ShaderType::AllGraphics, 0, bindingDesc, m_HdrBindingLayout, m_HdrBindingSet);

    for (int currentFrame = 0; currentFrame <= 1; currentFrame++)
    {
        bindingDesc.bindings.resize(0);
        bindingDesc
            .addItem(nvrhi::BindingSetItem::Texture_SRV(0, currentFrame ? renderTargets.DiffuseConfidence : renderTargets.PrevDiffuseConfidence))
            .addItem(nvrhi::BindingSetItem::Texture_SRV(1, currentFrame ? renderTargets.SpecularConfidence : renderTargets.PrevSpecularConfidence))
            .addItem(nvrhi::BindingSetItem::ConstantBuffer(0, m_ConstantBuffer));

        nvrhi::BindingSetHandle bindingSet;
        nvrhi::utils::CreateBindingSetAndLayout(device, nvrhi::ShaderType::AllGraphics, 0, bindingDesc, m_ConfidenceBindingLayout, bindingSet);

        if (currentFrame)
            m_ConfidenceBindingSet = bindingSet;
        else
            m_ConfidenceBindingSetPrev = bindingSet;
    }

    {
        m_WSRVPixelShader = shaderFactory.CreateShader("app/VisualizeWSR.hlsl", "main", nullptr, nvrhi::ShaderType::Pixel);
        
        auto cbd = nvrhi::utils::CreateVolatileConstantBufferDesc(sizeof(WSRVisualizationConstants), "WSRVisualizationConstants", 16);

        m_WSRVConstantBuffer = device->createBuffer(cbd);

        auto bindingDesc = nvrhi::BindingSetDesc()
            .addItem(nvrhi::BindingSetItem::Texture_SRV(0, renderTargets.Depth))
            .addItem(nvrhi::BindingSetItem::Texture_SRV(1, renderTargets.GBufferNormals))
            .addItem(nvrhi::BindingSetItem::Texture_SRV(2, renderTargets.GBufferGeoNormals))
            .addItem(nvrhi::BindingSetItem::Texture_UAV(0, rtxdiResources.debugTexture1))
            .addItem(nvrhi::BindingSetItem::Texture_UAV(1, rtxdiResources.debugTexture2))
            .addItem(nvrhi::BindingSetItem::ConstantBuffer(0, m_WSRVConstantBuffer))
            .addItem(nvrhi::BindingSetItem::StructuredBuffer_UAV(2, rtxdiResources.gridHashMapBuffer))
            ;

        nvrhi::utils::CreateBindingSetAndLayout(device, nvrhi::ShaderType::AllGraphics, 0, bindingDesc, m_WSRVLayout, m_WSRVSet);
    }
}

void VisualizationPass::Render(
    nvrhi::ICommandList* commandList,
    nvrhi::IFramebuffer* framebuffer,
    const IView& renderView,
    const IView& upscaledView,
    const rtxdi::ImportanceSamplingContext& isContext,
    uint32_t inputBufferIndex,
    uint32_t visualizationMode,
    bool enableAccumulation)
{
    if (visualizationMode == VIS_MODE_WS_GRID || 
        visualizationMode == VIS_MODE_ENV_VIS_DEBUG_1 || 
        visualizationMode == VIS_MODE_ENV_VIS_DEBUG_2)
    {
        if (m_WSRVPipeline == nullptr)
        {
            auto pipelineDesc = nvrhi::GraphicsPipelineDesc()
                .setVertexShader(m_VertexShader)
                .setPixelShader(m_WSRVPixelShader)
                .addBindingLayout(m_WSRVLayout)
                .setPrimType(nvrhi::PrimitiveType::TriangleStrip)
                .setRenderState(nvrhi::RenderState()
                    .setDepthStencilState(nvrhi::DepthStencilState().disableDepthTest().disableStencil())
                    .setRasterState(nvrhi::RasterState().setCullNone())
                    .setBlendState(nvrhi::BlendState().setRenderTarget(0, 
                        nvrhi::utils::CreateAddBlendState(nvrhi::BlendFactor::One, nvrhi::BlendFactor::InvSrcAlpha))));

            m_WSRVPipeline = m_Device->createGraphicsPipeline(pipelineDesc, framebuffer);
        }
        
        auto state = nvrhi::GraphicsState()
            .setPipeline(m_WSRVPipeline)
            .addBindingSet(m_WSRVSet)
            .setFramebuffer(framebuffer);

        static float3 s_cameraPositionPrev = renderView.GetViewOrigin();
        
        WSRVisualizationConstants constants = {};
        constants.visualizationMode = visualizationMode;
        renderView.FillPlanarViewConstants(constants.view);
        constants.sceneGridScale = 0.3f;

        {
            state.setViewport(upscaledView.GetViewportState());
            const auto& renderViewport = renderView.GetViewportState().viewports[0];
            const auto& upscaledViewport = upscaledView.GetViewportState().viewports[0];
            constants.resolutionScale.x = renderViewport.width() / upscaledViewport.width();
            constants.resolutionScale.y = renderViewport.height() / upscaledViewport.height();
        }

        commandList->writeBuffer(m_WSRVConstantBuffer, &constants, sizeof(constants));

        commandList->setGraphicsState(state);
        commandList->draw(nvrhi::DrawArguments().setVertexCount(4));

        s_cameraPositionPrev = renderView.GetViewOrigin();

        return;
    }

    if (m_HdrPipeline == nullptr || m_HdrPipeline->getFramebufferInfo() != framebuffer->getFramebufferInfo())
    {
        auto pipelineDesc = nvrhi::GraphicsPipelineDesc()
            .setVertexShader(m_VertexShader)
            .setPixelShader(m_HdrPixelShader)
            .addBindingLayout(m_HdrBindingLayout)
            .setPrimType(nvrhi::PrimitiveType::TriangleStrip)
            .setRenderState(nvrhi::RenderState()
                .setDepthStencilState(nvrhi::DepthStencilState().disableDepthTest().disableStencil())
                .setRasterState(nvrhi::RasterState().setCullNone())
                .setBlendState(nvrhi::BlendState().setRenderTarget(0, 
                    nvrhi::utils::CreateAddBlendState(nvrhi::BlendFactor::One, nvrhi::BlendFactor::InvSrcAlpha))));

        m_HdrPipeline = m_Device->createGraphicsPipeline(pipelineDesc, framebuffer);

        pipelineDesc.setPixelShader(m_ConfidencePixelShader);
        pipelineDesc.bindingLayouts.resize(0);
        pipelineDesc.addBindingLayout(m_ConfidenceBindingLayout);

        m_ConfidencePipeline = m_Device->createGraphicsPipeline(pipelineDesc, framebuffer);
    }

    bool confidence = 
        (visualizationMode == VIS_MODE_DIFFUSE_CONFIDENCE) ||
        (visualizationMode == VIS_MODE_SPECULAR_CONFIDENCE);

    auto state = nvrhi::GraphicsState()
        .setPipeline(confidence ? m_ConfidencePipeline : m_HdrPipeline)
        .addBindingSet(confidence ? m_ConfidenceBindingSet : m_HdrBindingSet)
        .setFramebuffer(framebuffer)
        .setViewport(upscaledView.GetViewportState());

    VisualizationConstants constants = {};
    constants.outputSize.x = upscaledView.GetViewExtent().width();
    constants.outputSize.y = upscaledView.GetViewExtent().height();
    const auto& renderViewport = renderView.GetViewportState().viewports[0];
    const auto& upscaledViewport = upscaledView.GetViewportState().viewports[0];
    constants.resolutionScale.x = renderViewport.width() / upscaledViewport.width();
    constants.resolutionScale.y = renderViewport.height() / upscaledViewport.height();
    constants.restirDIReservoirBufferParams = isContext.getReSTIRDIContext().getReservoirBufferParameters();
    constants.restirGIReservoirBufferParams = isContext.getReSTIRGIContext().getReservoirBufferParameters();
    constants.visualizationMode = visualizationMode;
    constants.inputBufferIndex = inputBufferIndex;
    constants.enableAccumulation = enableAccumulation;
    commandList->writeBuffer(m_ConstantBuffer, &constants, sizeof(constants));

    commandList->setGraphicsState(state);
    commandList->draw(nvrhi::DrawArguments().setVertexCount(4));
}

void VisualizationPass::NextFrame()
{
    std::swap(m_ConfidenceBindingSet, m_ConfidenceBindingSetPrev);
}
