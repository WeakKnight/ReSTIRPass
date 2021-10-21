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
    return reflector;
}

void ReSTIRPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (mpScene == nullptr)
    {
        return;
    }

    mpGBufferPass->Execute(pRenderContext);

    Texture::SharedPtr shadingOutput = renderData[kOutput]->asTexture();

    {
        PROFILE("Shading");

        auto cb = mpShadingPass["CB"];
        cb["gViewportDims"] = uint2(gpFramework->getTargetFbo()->getWidth(), gpFramework->getTargetFbo()->getHeight());
        cb["gFrameIndex"] = (uint)gpFramework->getGlobalClock().getFrame();
        //cb["gParams"]["tileSize"] = 512u;
        //cb["gParams"]["tileCount"] = 128u;
        //cb["gParams"]["reservoirBlockRowPitch"] = reservoirBlockRowPitch;
        //cb["gParams"]["reservoirArrayPitch"] = reservoirArrayPitch;
        /*cb["gInputBufferIndex"] = shadeInputBufferIndex;*/
        mpGBufferPass->SetShaderData(cb["gGBuffer"]);
        mpShadingPass["gShadingOutput"] = shadingOutput;

        mpShadingPass->execute(pRenderContext, gpFramework->getTargetFbo()->getWidth(), gpFramework->getTargetFbo()->getHeight());
    }
}

void ReSTIRPass::renderUI(Gui::Widgets& widget)
{
}

void ReSTIRPass::setScene(RenderContext* pRenderContext, const Scene::SharedPtr& pScene)
{
    mpScene = pScene;

    mpGBufferPass = GBufferPass::Create(mpScene);

    mpSampleGenerator = SampleGenerator::create(SAMPLE_GENERATOR_UNIFORM);

    Shader::DefineList defines = mpScene->getSceneDefines();
    defines.add(mpSampleGenerator->getDefines());
    defines.add("_MS_DISABLE_ALPHA_TEST");
    defines.add("_DEFAULT_ALPHA_TEST");
    if (mEnablePresampling)
    {
        defines.add("_PRE_SAMPLING");
    }

    {
        Program::Desc desc;
        desc.addShaderLibrary("RenderPasses/ReSTIRPass/Shading.cs.slang").csEntry("main").setShaderModel("6_5");
        mpShadingPass = ComputePass::create(desc, defines);
    }
}
