#include "Utils/Math/MathConstants.slangh"
import Scene.Shading;
import Utils.Math.MathHelpers;
import Utils.Color.ColorHelpers;

bool isReprjTextureCoordValid(uint2 texCoord, uint2 texDim)
{
    bool insideScreen = (texCoord.x >= 0 && texCoord.y >= 0 && texCoord.x < texDim.x && texCoord.y < texDim.y);
    if(!insideScreen)
    {
        return false;
    }

    return true;
}

bool isReprjNormalValid(float3 a, float3 b, float normalThreshold = 0.65)
{
    // check normals for compatibility
    if (dot(a, b) < normalThreshold) 
    {
        return false;
    }

    return true;
}

bool isReprjPositionValid(float3 a, float3 b, float positionThreshold = 0.1)
{
    float3 a2b = b - a;
    // check positions for compatibility
    if (dot(a2b, a2b) > (positionThreshold * positionThreshold)) 
    {
        return false;
    }

    return true;
}

bool areMaterialsSimilar(ShadingData a, ShadingData b)
{
    const float roughnessThreshold = 0.5;
    const float reflectivityThreshold = 0.5;
    const float albedoThreshold = 0.5;
    if (!compareRelativeDifference(a.linearRoughness, b.linearRoughness, roughnessThreshold))
        return false;
    if (!compareRelativeDifference(luminance(a.specular), luminance(b.specular), reflectivityThreshold))
        return false;
    
    if (!compareRelativeDifference(luminance(a.diffuse), luminance(b.diffuse), albedoThreshold))
        return false;
    return true;
}

// Compares two values and returns true if their relative difference is lower than the threshold.
// Zero or negative threshold makes test always succeed, not fail.
bool compareRelativeDifference(float reference, float candidate, float threshold)
{
    return (threshold <= 0) || abs(reference - candidate) <= threshold * reference;
}
