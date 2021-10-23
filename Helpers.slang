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
    // check normals for compatibility
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

// Pack [0.0, 1.0] float to a uint of a given bit depth
#define PACK_UFLOAT_TEMPLATE(size)                      \
uint Pack_R ## size ## _UFLOAT(float r, float d = 0.5f) \
{                                                       \
    const uint mask = (1U << size) - 1U;                \
                                                        \
    return (uint)floor(r * mask + d) & mask;            \
}                                                       \
                                                        \
float Unpack_R ## size ## _UFLOAT(uint r)               \
{                                                       \
    const uint mask = (1U << size) - 1U;                \
                                                        \
    return (float)(r & mask) / (float)mask;             \
}

PACK_UFLOAT_TEMPLATE(8)
PACK_UFLOAT_TEMPLATE(10)
PACK_UFLOAT_TEMPLATE(11)
PACK_UFLOAT_TEMPLATE(16)

uint Pack_R11G11B10_UFLOAT(float3 rgb, float3 d = float3(0.5f, 0.5f, 0.5f))
{
    uint r = Pack_R11_UFLOAT(rgb.r, d.r);
    uint g = Pack_R11_UFLOAT(rgb.g, d.g) << 11;
    uint b = Pack_R10_UFLOAT(rgb.b, d.b) << 22;
    return r | g | b;
}

float3 Unpack_R11G11B10_UFLOAT(uint rgb)
{
    float r = Unpack_R11_UFLOAT(rgb);
    float g = Unpack_R11_UFLOAT(rgb >> 11);
    float b = Unpack_R10_UFLOAT(rgb >> 22);
    return float3(r, g, b);
}

uint Pack_R8G8B8A8_Gamma_UFLOAT(float4 rgba, float gamma = 2.2, float4 d = float4(0.5f, 0.5f, 0.5f, 0.5f))
{
    rgba = pow(saturate(rgba), 1.0 / gamma);
    uint r = Pack_R8_UFLOAT(rgba.r, d.r);
    uint g = Pack_R8_UFLOAT(rgba.g, d.g) << 8;
    uint b = Pack_R8_UFLOAT(rgba.b, d.b) << 16;
    uint a = Pack_R8_UFLOAT(rgba.a, d.a) << 24;
    return r | g | b | a;
}

float4 Unpack_R8G8B8A8_Gamma_UFLOAT(uint rgba, float gamma = 2.2)
{
    float r = Unpack_R8_UFLOAT(rgba);
    float g = Unpack_R8_UFLOAT(rgba >> 8);
    float b = Unpack_R8_UFLOAT(rgba >> 16);
    float a = Unpack_R8_UFLOAT(rgba >> 24);
    float4 v = float4(r, g, b, a);
    v = pow(saturate(v), gamma);
    return v;
}

// Compares two values and returns true if their relative difference is lower than the threshold.
// Zero or negative threshold makes test always succeed, not fail.
bool compareRelativeDifference(float reference, float candidate, float threshold)
{
    return (threshold <= 0) || abs(reference - candidate) <= threshold * reference;
}

// "Explodes" an integer, i.e. inserts a 0 between each bit.  Takes inputs up to 16 bit wide.
//      For example, 0b11111111 -> 0b1010101010101010
uint integerExplode(uint x)
{
    x = (x | (x << 8)) & 0x00FF00FF;
    x = (x | (x << 4)) & 0x0F0F0F0F;
    x = (x | (x << 2)) & 0x33333333;
    x = (x | (x << 1)) & 0x55555555;
    return x;
}

// Reverse of IntegerExplode, i.e. takes every other bit in the integer and compresses
// those bits into a dense bit firld. Takes 32-bit inputs, produces 16-bit outputs.
//    For example, 0b'abcdefgh' -> 0b'0000bdfh'
uint integerCompact(uint x)
{
    x = (x & 0x11111111) | ((x & 0x44444444) >> 1);
    x = (x & 0x03030303) | ((x & 0x30303030) >> 2);
    x = (x & 0x000F000F) | ((x & 0x0F000F00) >> 4);
    x = (x & 0x000000FF) | ((x & 0x00FF0000) >> 8);
    return x;
}

// Converts a 2D position to a linear index following a Z-curve pattern.
uint ZCurveToLinearIndex(uint2 xy)
{
    return integerExplode(xy[0]) | (integerExplode(xy[1]) << 1);
}

// Converts a linear to a 2D position following a Z-curve pattern.
uint2 linearIndexToZCurve(uint index)
{
    return uint2(
        integerCompact(index),
        integerCompact(index >> 1));
}

// 32 bit Jenkins hash
uint jenkinsHash(uint a)
{
    // http://burtleburtle.net/bob/hash/integer.html
    a = (a + 0x7ed55d16) + (a << 12);
    a = (a ^ 0xc761c23c) ^ (a >> 19);
    a = (a + 0x165667b1) + (a << 5);
    a = (a + 0xd3a2646c) ^ (a << 9);
    a = (a + 0xfd7046c5) + (a << 3);
    a = (a ^ 0xb55a4f09) ^ (a >> 16);
    return a;
}

void cartesianToSpherical(float3 cartesian, out float r, out float azimuth, out float elevation)
{
    r = length(cartesian);
    cartesian /= r;

    azimuth = atan2(cartesian.z, cartesian.x);
    elevation = asin(cartesian.y);
}

float3 sphericalToCartesian(float r, float azimuth, float elevation)
{
    float sinAz, cosAz, sinEl, cosEl;
    sincos(azimuth, sinAz, cosAz);
    sincos(elevation, sinEl, cosEl);

    float x = r * cosAz * cosEl;
    float y = r * sinEl;
    float z = r * sinAz * cosEl;

    return float3(x, y, z);
}

float3 cosineWeightedSampling(float2 XY, float3 N, out float pdf)
{
    float3 w = N;
    float3 u = 0.0;
    if (abs(w.x) > 0.1)
    {
        u = normalize(cross(float3(0.0, 1.0, 0.0), w));
    }
    else
    {
        u = normalize(cross(float3(1.0, 0.0, 0.0), w));
    }
    float3 v = cross(w, u);
    float r1 = 2.0 * M_PI * XY.x;
    float r2 = XY.y;
    float r2s = sqrt(r2);
    float3 dir = normalize((u * cos(r1) * r2s + v * sin(r1) * r2s + w * sqrt(1.0 - r2)));

    pdf = dot(N, dir) / M_PI;

    return dir;
}