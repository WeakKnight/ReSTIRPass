#pragma once
#include "Falcor.h"
using namespace Falcor;

class ShadingDataLoader
{
public:
    static void setShaderData(const RenderData& renderData, Texture::SharedPtr VBufferPrev, const ShaderVar& var);
};


