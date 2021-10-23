#include "ShadingDataLoader.h"

void ShadingDataLoader::setShaderData(const RenderData& renderData, const ShaderVar& var)
{
    var["VBuffer"] = renderData["vbuffer"]->asTexture();
}
