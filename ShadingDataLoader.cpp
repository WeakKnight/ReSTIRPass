#include "ShadingDataLoader.h"

void ShadingDataLoader::setShaderData(const RenderData& renderData, const ShaderVar& var)
{
    var["worldPosition"] = renderData["posW"]->asTexture();
    var["worldShadingNormal"] = renderData["normalW"]->asTexture();
    var["worldFaceNormal"] = renderData["faceNormalW"]->asTexture();
    var["materialDiffuseOpacity"] = renderData["mtlDiffOpacity"]->asTexture();
    var["materialSpecularRoughness"] = renderData["mtlSpecRough"]->asTexture();
    var["materialEmissive"] = renderData["mtlEmissive"]->asTexture();
    var["materialExtraParams"] = renderData["mtlParams"]->asTexture();
}
