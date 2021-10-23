#include "ShadingDataLoader.h"

void ShadingDataLoader::setShaderData(const RenderData& renderData, Texture::SharedPtr VBufferPrev, const ShaderVar& var)
{
    var["VBuffer"] = renderData["vbuffer"]->asTexture();
    var["VBufferPrev"] = VBufferPrev;
    var["motionVector"] = renderData["motionVecs"]->asTexture();
}
