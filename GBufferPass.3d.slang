import Scene.Shading;
import Scene.Raster;
import Scene.TextureSampler;
import Utils.Math.MathHelpers;
import Utils.Math.PackedFormats;
#include "Scene/Material/MaterialDefines.slangh"

import Helpers;

cbuffer PerFrameCB
{
    float2  frameSize;
    float3  cameraPos;
};

RasterizerOrderedTexture2D<float2> gMotionVectors;

struct GBuffer 
{
	float4 albedo    : SV_Target0;
    float metallic: SV_Target1;
    float4 positon   : SV_Target2;
    float4 normal    : SV_Target3;
    float4 emissive  : SV_Target4;
    float4 faceN     : SV_Target5;
    float4 linearZAndNormal: SV_Target6;
};

VSOut vsMain(VSIn vsIn)
{
    return defaultVS(vsIn);
}

[earlydepthstencil]
GBuffer psMain(VSOut vOut, uint triangleIndex : SV_PrimitiveID)
{
    int2 ipos = int2(vOut.posH.xy);

    float3 faceNormal = gScene.getFaceNormalW(vOut.instanceID, triangleIndex);
    VertexData v = prepareVertexData(vOut, faceNormal);

    if (alphaTest(v, gScene.materials[vOut.materialID], gScene.materialResources[vOut.materialID])) 
    {
        discard;
    }

    float3 viewDir = normalize(gScene.camera.getPosition() - vOut.posW);
    ShadingData sd = prepareShadingData(vOut, triangleIndex, viewDir);

    adjustShadingNormal(sd, v);

    float packedSpecular = asfloat(Pack_R8G8B8A8_Gamma_UFLOAT(float4(sd.specular, sd.linearRoughness)));

    GBuffer gBufOut;
	gBufOut.albedo     = float4(sd.diffuse, sd.opacity);
    gBufOut.metallic = sd.metallic;
    gBufOut.positon    = float4(sd.posW, packedSpecular);
    gBufOut.normal     = float4(sd.N, length(sd.posW - cameraPos));
    gBufOut.emissive   = float4(sd.emissive, 1.0);
    gBufOut.faceN      = float4(sd.faceN, sd.frontFacing? 1.0f: 0.0f);                  
    
    // Motion Vectors
    const float2 pixelPos = ipos + float2(0.5, 0.5); // Current sample in pixel coords.
    const float4 prevPosH = vOut.prevPosH; // Sample in previous frame in clip space coords, no jittering applied.
    const float2 mv = calcMotionVector(pixelPos, prevPosH, frameSize) + float2(gScene.camera.data.jitterX, -gScene.camera.data.jitterY); // Remove camera jitter from motion vector
    gMotionVectors[ipos] = mv;

    // Linear z and its derivative
    float linearZ = vOut.posH.z * vOut.posH.w;
    float2 linearZAndDeriv = float2(linearZ, max(abs(ddx(linearZ)), abs(ddy(linearZ))));
    // gLinearZAndDeriv[ipos] = linearZAndDeriv;
    float2 packedNormal = ndir_to_oct_snorm(gBufOut.normal.xyz);
    gBufOut.linearZAndNormal = float4(linearZAndDeriv, packedNormal);

    return gBufOut;
}
