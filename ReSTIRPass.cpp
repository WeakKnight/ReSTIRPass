/***************************************************************************
 # Copyright (c) 2015-21, NVIDIA CORPORATION. All rights reserved.
 #
 # Redistribution and use in source and binary forms, with or without
 # modification, are permitted provided that the following conditions
 # are met:
 #  * Redistributions of source code must retain the above copyright
 #    notice, this list of conditions and the following disclaimer.
 #  * Redistributions in binary form must reproduce the above copyright
 #    notice, this list of conditions and the following disclaimer in the
 #    documentation and/or other materials provided with the distribution.
 #  * Neither the name of NVIDIA CORPORATION nor the names of its
 #    contributors may be used to endorse or promote products derived
 #    from this software without specific prior written permission.
 #
 # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS "AS IS" AND ANY
 # EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 # IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 # PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 # CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 # EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 # PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 # PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 # OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 # (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 # OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 **************************************************************************/
#include "ReSTIRPass.h"
#include "Helpers.h"

namespace
{
    const char kDesc[] = "ReSTIR Pass";
    const char kOutput[] = "output";
    const char kMotionVector[] = "motion";
}

// Don't remove this. it's required for hot-reload to function properly
extern "C" __declspec(dllexport) const char* getProjDir()
{
    return PROJECT_DIR;
}

extern "C" __declspec(dllexport) void getPasses(Falcor::RenderPassLibrary& lib)
{
    lib.registerClass("ReSTIRPass", kDesc, ReSTIRPass::create);
}

ReSTIRPass::SharedPtr ReSTIRPass::create(RenderContext* pRenderContext, const Dictionary& dict)
{
    SharedPtr pPass = SharedPtr(new ReSTIRPass);
    return pPass;
}

std::string ReSTIRPass::getDesc() { return kDesc; }

Dictionary ReSTIRPass::getScriptingDictionary()
{
    return Dictionary();
}

RenderPassReflection ReSTIRPass::reflect(const CompileData& compileData)
{
    // Define the required resources here
    RenderPassReflection reflector;
    reflector.addOutput(kOutput, "Output").bindFlags(ResourceBindFlags::RenderTarget | ResourceBindFlags::UnorderedAccess | ResourceBindFlags::ShaderResource).format(ResourceFormat::RGBA32Float);
    reflector.addOutput(kMotionVector, "Motion Vectors").bindFlags(ResourceBindFlags::UnorderedAccess | ResourceBindFlags::ShaderResource).format(ResourceFormat::RG32Float);
    return reflector;
}

void ReSTIRPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (mpScene == nullptr)
    {
        return;
    }

    {
        PROFILE("Update Lights");
        
        if (is_set(mpScene->getUpdates(), Scene::UpdateFlags::EnvMapChanged))
        {
            mpEnvMapSampler = nullptr;
        }
        if (mpScene->useEnvLight())
        {
            if (!mpEnvMapSampler)
            {
                mpEnvMapSampler = EnvMapSampler::create(pRenderContext, mpScene->getEnvMap());
            }
        }
        if (!mpEmissiveSampler)
        {
            mpScene->getLightCollection(pRenderContext)->prepareSyncCPUData(pRenderContext);
            mpEmissiveSampler = EmissivePowerSampler::create(pRenderContext, mpScene);
            CreatePasses();
        }
        mpEmissiveSampler->update(pRenderContext);
    }

    {
        PROFILE("GBuffer");
        Texture::SharedPtr motionTexture = renderData[kMotionVector]->asTexture();
        mpGBufferPass->Execute(pRenderContext, motionTexture);
    }

    uint32_t renderWidth = gpFramework->getTargetFbo()->getWidth();
    uint32_t renderHeight = gpFramework->getTargetFbo()->getHeight();
    uint32_t renderWidthBlocks = (renderWidth + 16 - 1) / 16;
    uint32_t renderHeightBlocks = (renderHeight + 16 - 1) / 16;
    uint reservoirBlockRowPitch = renderWidthBlocks * (16 * 16);
    uint reservoirArrayPitch = reservoirBlockRowPitch * renderHeightBlocks;

    if (mpReservoirBuffer == nullptr)
    {
        const uint32_t reservoirLayers = 2;
        mpReservoirBuffer = Buffer::createStructured(mpShadingPass["gReservoirs"], reservoirArrayPitch * reservoirLayers);
        mpReservoirBuffer->setName("ReSTIR: Reservoir Buffer");
    }

    if (mNeedUpdateDefines)
    {
        UpdateDefines();
    }

    mLastFrameOutputReservoir = mCurrentFrameOutputReservoir;

    uint32_t initialOutputBufferIndex = !mLastFrameOutputReservoir;
    uint32_t temporalInputBufferIndex = mLastFrameOutputReservoir;
    uint32_t temporalOutputBufferIndex = initialOutputBufferIndex;
    uint32_t spatialInputBufferIndex = temporalOutputBufferIndex;
    uint32_t spatialOutputBufferIndex = !spatialInputBufferIndex;
    uint32_t shadeInputBufferIndex = mEnableSpatialResampling ? spatialOutputBufferIndex : temporalOutputBufferIndex;

    mCurrentFrameOutputReservoir = shadeInputBufferIndex;

    {
        PROFILE("Initial Sampling");
        auto cb = mpInitialSamplingPass["CB"];
        cb["gViewportDims"] = uint2(gpFramework->getTargetFbo()->getWidth(), gpFramework->getTargetFbo()->getHeight());
        cb["gFrameIndex"] = (uint)gpFramework->getGlobalClock().getFrame();
        cb["gParams"]["reservoirBlockRowPitch"] = reservoirBlockRowPitch;
        cb["gParams"]["reservoirArrayPitch"] = reservoirArrayPitch;
        cb["gOutputBufferIndex"] = initialOutputBufferIndex;
        mpGBufferPass->SetShaderData(cb["gGBuffer"]);
        mpEnvMapSampler->setShaderData(cb["gEnvMapSampler"]);
        mpEmissiveSampler->setShaderData(cb["gEmissiveLightSampler"]);
        mpScene->setRaytracingShaderData(pRenderContext, mpInitialSamplingPass->getRootVar());
        mpInitialSamplingPass["gReservoirs"] = mpReservoirBuffer;
        mpInitialSamplingPass->execute(pRenderContext, gpFramework->getTargetFbo()->getWidth(), gpFramework->getTargetFbo()->getHeight());
    }

    if (mEnableTemporalResampling)
    {
        PROFILE("Temporal Resampling");
        auto cb = mpTemporalResamplingPass["CB"];
        cb["gViewportDims"] = uint2(gpFramework->getTargetFbo()->getWidth(), gpFramework->getTargetFbo()->getHeight());
        cb["gFrameIndex"] = (uint)gpFramework->getGlobalClock().getFrame();
        cb["gParams"]["reservoirBlockRowPitch"] = reservoirBlockRowPitch;
        cb["gParams"]["reservoirArrayPitch"] = reservoirArrayPitch;
        cb["gInputBufferIndex"] = initialOutputBufferIndex;
        cb["gHistoryBufferIndex"] = temporalInputBufferIndex;
        cb["gOutputBufferIndex"] = temporalOutputBufferIndex;
        mpGBufferPass->SetShaderData(cb["gGBuffer"]);
        mpEnvMapSampler->setShaderData(cb["gEnvMapSampler"]);
        mpEmissiveSampler->setShaderData(cb["gEmissiveLightSampler"]);
        mpScene->setRaytracingShaderData(pRenderContext, mpTemporalResamplingPass->getRootVar());
        mpTemporalResamplingPass["gReservoirs"] = mpReservoirBuffer;
        mpTemporalResamplingPass->execute(pRenderContext, gpFramework->getTargetFbo()->getWidth(), gpFramework->getTargetFbo()->getHeight());
    }

    if (mEnableSpatialResampling)
    {
        PROFILE("Spatial Resampling");
    }

    {
        PROFILE("Shading");

        Texture::SharedPtr shadingOutput = renderData[kOutput]->asTexture();

        auto cb = mpShadingPass["CB"];
        cb["gViewportDims"] = uint2(gpFramework->getTargetFbo()->getWidth(), gpFramework->getTargetFbo()->getHeight());
        cb["gFrameIndex"] = (uint)gpFramework->getGlobalClock().getFrame();
        cb["gParams"]["reservoirBlockRowPitch"] = reservoirBlockRowPitch;
        cb["gParams"]["reservoirArrayPitch"] = reservoirArrayPitch;
        cb["gInputBufferIndex"] = shadeInputBufferIndex;
        mpGBufferPass->SetShaderData(cb["gGBuffer"]);
        mpEnvMapSampler->setShaderData(cb["gEnvMapSampler"]);
        mpEmissiveSampler->setShaderData(cb["gEmissiveLightSampler"]);
        mpShadingPass["gReservoirs"] = mpReservoirBuffer;
        mpShadingPass["gShadingOutput"] = shadingOutput;
        mpScene->setRaytracingShaderData(pRenderContext, mpShadingPass->getRootVar());
        mpShadingPass->execute(pRenderContext, gpFramework->getTargetFbo()->getWidth(), gpFramework->getTargetFbo()->getHeight());
    }
}

void ReSTIRPass::renderUI(Gui::Widgets& widget)
{
    bool dirty = false;

    if (auto group = widget.group("Initial Sampling"))
    {
        dirty |= group.var("Initial Emissive Triangle Samples", mInitialEmissiveTriangleSamples, 1u, 32u);
        dirty |= group.var("Initial EnvMap Samples", mInitialEnvMapSamples, 1u, 32u);
        
    }

    if (auto group = widget.group("Temporal Resampling"))
    {
        group.checkbox("Enable Temporal Resampling", mEnableTemporalResampling);
    }

    if (auto group = widget.group("Spatial Resampling"))
    {
        group.checkbox("Enable Spatial Resampling", mEnableSpatialResampling);
    }

    if (auto group = widget.group("Shading"))
    {
        dirty |= group.checkbox("Store Final Visibility", mStoreFinalVisibility);
    }

    mNeedUpdateDefines = dirty;
}

void ReSTIRPass::setScene(RenderContext* pRenderContext, const Scene::SharedPtr& pScene)
{
    mpScene = pScene;
    mpGBufferPass = GBufferPass::Create(mpScene);
    mpSampleGenerator = SampleGenerator::create(SAMPLE_GENERATOR_UNIFORM);

    std::vector<uint8_t> offsets;
    offsets.resize(8192 * 2);
    FillNeighborOffsetBuffer(offsets.data());
    mpNeighborOffsetBuffer = Buffer::createTyped(ResourceFormat::RG8Snorm, 8192, ResourceBindFlags::ShaderResource | ResourceBindFlags::UnorderedAccess, Buffer::CpuAccess::None, offsets.data());
    mpNeighborOffsetBuffer->setName("ReSTIR: Neighbor Offset Buffer");
    
    CreatePasses();
}

void ReSTIRPass::AddDefines(ComputePass::SharedPtr pass, Shader::DefineList& defines)
{
    pass->getProgram()->addDefines(defines);
    pass->setVars(nullptr);
}

void ReSTIRPass::RemoveDefines(ComputePass::SharedPtr pass, Shader::DefineList& defines)
{
    pass->getProgram()->removeDefines(defines);
    pass->setVars(nullptr);
}

void ReSTIRPass::CreatePass(ComputePass::SharedPtr& pass, const char* path, Shader::DefineList& defines)
{
    Program::Desc desc;
    desc.addShaderLibrary(path).csEntry("main").setShaderModel("6_5");
    pass = ComputePass::create(desc, defines, false);
}

void ReSTIRPass::CreatePasses()
{
    Shader::DefineList defines = mpScene->getSceneDefines();
    defines.add(mpSampleGenerator->getDefines());
    defines.add("_MS_DISABLE_ALPHA_TEST");
    defines.add("_DEFAULT_ALPHA_TEST");
    if (mEnablePresampling)
    {
        defines.add("_PRE_SAMPLING");
    }
    if (mpEmissiveSampler)
    {
        defines.add(mpEmissiveSampler->getDefines());
    }

    CreatePass(mpInitialSamplingPass, "RenderPasses/ReSTIRPass/InitialSampling.cs.slang", defines);
    CreatePass(mpTemporalResamplingPass, "RenderPasses/ReSTIRPass/TemporalResampling.cs.slang", defines);
    CreatePass(mpShadingPass, "RenderPasses/ReSTIRPass/Shading.cs.slang", defines);

    UpdateDefines();
}

void ReSTIRPass::UpdateDefines()
{
    {
        const char* kInitialEmissiveTriangleSamples = "_INITIAL_EMISSIVE_TRIANGLE_SAMPLES";
        const char* kInitialEnvMapSamples = "_INITIAL_ENVMAP_SAMPLES";
        Shader::DefineList defines;
        defines.add(kInitialEmissiveTriangleSamples, std::to_string(mInitialEmissiveTriangleSamples));
        defines.add(kInitialEnvMapSamples, std::to_string(mInitialEnvMapSamples));        
        AddDefines(mpInitialSamplingPass, defines);
    }

    {
        Shader::DefineList defines;
        AddDefines(mpTemporalResamplingPass, defines);
    }

    {
        const char* kStoreFinalVisibility = "_STORE_FINAL_VISIBILITY";
        Shader::DefineList defines;
        defines.add(kStoreFinalVisibility, mStoreFinalVisibility ? "1" : "0");
        AddDefines(mpShadingPass, defines);
    }

    mNeedUpdateDefines = false;
}
