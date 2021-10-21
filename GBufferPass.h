#pragma once
#include "DepthPrePass.h"

class GBufferPass : public std::enable_shared_from_this<GBufferPass>
{
public:
    using SharedPtr = std::shared_ptr<GBufferPass>;
    static GBufferPass::SharedPtr Create(Scene::SharedPtr scene);

    void Resize(uint32_t width, uint32_t height);

    void Execute(RenderContext* renderContext);

    void SetShaderData(const ShaderVar& var) const;

    inline Texture::SharedPtr GetShadingNormalTexture() { return m_Fbo->getColorTexture(3); }
    inline Texture::SharedPtr GetMotionTexture() { return m_MotionTexture; }
    inline Texture::SharedPtr GetDepthTexture() { return m_Fbo->getDepthStencilTexture(); }
    inline Texture::SharedPtr GetLinearNormalTexture() { return m_Fbo->getColorTexture(6); }
    inline Texture::SharedPtr GetPrevLinearNormalTexture() { return m_InternalPreviousLinearZAndNormalRT; }

    inline Texture::SharedPtr GetPrevAlbedoTex()
    {
        return m_PreAlbedoTex;
    }

private:

    void InitPipelineResource();

    Scene::SharedPtr mpScene;

    Texture::SharedPtr              m_PreAlbedoTex;
    Texture::SharedPtr              m_PreMetalRoughTex;

    Fbo::SharedPtr                  m_Fbo;
    Texture::SharedPtr              m_MotionTexture;
    Texture::SharedPtr              m_InternalPreviousLinearZAndNormalRT;

    GraphicsProgram::SharedPtr      m_Program = nullptr;
    GraphicsVars::SharedPtr         m_ProgramVars = nullptr;
    GraphicsState::SharedPtr        m_GraphicsState = nullptr;

    RasterizerState::SharedPtr      m_RasterizerState = nullptr;
    DepthStencilState::SharedPtr    m_DepthStencilState = nullptr;

    DepthPrePass::SharedPtr            m_DepthPass;
};


