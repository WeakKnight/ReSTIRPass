#include "GBufferPass.h"

GBufferPass::SharedPtr GBufferPass::Create(Scene::SharedPtr scene)
{
    GBufferPass::SharedPtr result = SharedPtr(new GBufferPass());

    result->mpScene = scene;
    result->Resize(gpFramework->getTargetFbo()->getWidth(), gpFramework->getTargetFbo()->getHeight());
    result->InitPipelineResource();

    return result;
}

/*
Create FBO And Relavant Resources
*/
void GBufferPass::Resize(uint32_t width, uint32_t height)
{
    if (m_DepthPass)
    {
        m_DepthPass->Resize(width, height);
    }

    Fbo::Desc desc;
    desc.setSampleCount(0);
    desc.setColorTarget(0, Falcor::ResourceFormat::RGBA16Float);    // Albedo
    desc.setColorTarget(1, Falcor::ResourceFormat::R8Unorm);       // Metal
    desc.setColorTarget(2, Falcor::ResourceFormat::RGBA32Float);    // Pos + Spec Roughness
    desc.setColorTarget(3, Falcor::ResourceFormat::RGBA16Float);    // Normal
    desc.setColorTarget(4, Falcor::ResourceFormat::RGBA16Float);    // Emissive
    desc.setColorTarget(5, Falcor::ResourceFormat::RGBA16Float);    // FaceN
    desc.setColorTarget(6, Falcor::ResourceFormat::RGBA32Float);    // LinearZ And Normal
    desc.setDepthStencilTarget(ResourceFormat::D32Float);

    m_PreAlbedoTex = Texture::create2D(width, height, ResourceFormat::RGBA16Float, 1U, 1U, nullptr, Resource::BindFlags::RenderTarget | ResourceBindFlags::ShaderResource);
    m_PreMetalRoughTex = Texture::create2D(width, height, ResourceFormat::RG8Unorm, 1U, 1U, nullptr, Resource::BindFlags::RenderTarget | ResourceBindFlags::ShaderResource);

    m_Fbo = Fbo::create2D(width, height, desc);

    m_MotionTexture = Texture::create2D(width, height, ResourceFormat::RG32Float, 1U, 1U, nullptr, ResourceBindFlags::UnorderedAccess | ResourceBindFlags::ShaderResource);
    m_MotionTexture->setName("Motion Texture");

    m_InternalPreviousLinearZAndNormalRT = Texture::create2D(width, height, ResourceFormat::RGBA32Float, 1, 1, nullptr, Resource::BindFlags::RenderTarget | Resource::BindFlags::ShaderResource);
}

void GBufferPass::Execute(RenderContext* renderContext, Texture::SharedPtr motionTexture)
{
    m_MotionTexture = motionTexture;

    Camera::SharedPtr camera = mpScene->getCamera();

    renderContext->blit(m_Fbo->getColorTexture(6)->getSRV(),
        m_InternalPreviousLinearZAndNormalRT->getRTV());

    m_GraphicsState->setFbo(m_Fbo);

    m_ProgramVars["gMotionVectors"] = m_MotionTexture;
    m_ProgramVars["PerFrameCB"]["frameSize"] = float2(gpFramework->getTargetFbo()->getWidth(), gpFramework->getTargetFbo()->getHeight());
    m_ProgramVars["PerFrameCB"]["cameraPos"] = camera->getPosition();

    const float4 clearColor(0.0f, 0.0f, 0.0f, 0.0f);
    renderContext->clearFbo(m_Fbo.get(), clearColor, 1.0f, 0, FboAttachmentType::Color);
    renderContext->clearUAV(m_MotionTexture->getUAV().get(), float4(0.f));

    m_DepthPass->Execute(renderContext);
    m_Fbo->attachDepthStencilTarget(m_DepthPass->GetDepthTexture());
    m_GraphicsState->setFbo(m_Fbo);

    mpScene->rasterize(renderContext, m_GraphicsState.get(), m_ProgramVars.get());
}

void GBufferPass::SetShaderData(const ShaderVar& var) const
{
    var["_TexAlbedo"].setTexture(m_Fbo->getColorTexture(0));
    var["_TexMetallic"].setTexture(m_Fbo->getColorTexture(1));
    var["_TexPosition"].setTexture(m_Fbo->getColorTexture(2));
    var["_TexShadingNormal"].setTexture(m_Fbo->getColorTexture(3));
    var["_TexEmissive"].setTexture(m_Fbo->getColorTexture(4));
    var["_TexFaceNormal"].setTexture(m_Fbo->getColorTexture(5));
    var["_TexLinearZAndNormal"].setTexture(m_Fbo->getColorTexture(6));
    var["_TexMotion"].setTexture(m_MotionTexture);

    var["_TexPreAlbedo"].setTexture(m_PreAlbedoTex);
    var["_TexPreMetalRough"].setTexture(m_PreMetalRoughTex);
    var["_TexPreLinearZAndNormal"].setTexture(m_InternalPreviousLinearZAndNormalRT);
}

void GBufferPass::InitPipelineResource()
{
    m_DepthPass = DepthPrePass::Create(mpScene);

    Program::DefineList defines = { { "_DEFAULT_ALPHA_TEST", "" } };
    Program::Desc desc;
    desc.addShaderLibrary("RenderPasses/ReSTIRPass/GBufferPass.3d.slang").vsEntry("vsMain").psEntry("psMain");
    desc.setShaderModel("6_2");
    m_Program = GraphicsProgram::create(desc, defines);

    m_GraphicsState = GraphicsState::create();
    m_GraphicsState->setProgram(m_Program);

    RasterizerState::Desc rasterStateDesc;
    rasterStateDesc.setCullMode(RasterizerState::CullMode::Back);
    m_RasterizerState = RasterizerState::create(rasterStateDesc);

    DepthStencilState::Desc depthStancilDesc;
    depthStancilDesc.setDepthFunc(ComparisonFunc::Equal).setDepthWriteMask(false);
    m_DepthStencilState = DepthStencilState::create(depthStancilDesc);

    m_Program->addDefines(mpScene->getSceneDefines());
    m_ProgramVars = GraphicsVars::create(m_Program->getReflector());

    m_GraphicsState->setRasterizerState(m_RasterizerState);
    m_GraphicsState->setDepthStencilState(m_DepthStencilState);

    m_GraphicsState->setProgram(m_Program);
}
