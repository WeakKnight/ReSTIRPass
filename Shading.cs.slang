#include "Utils/Math/MathConstants.slangh"
import Utils.Sampling.SampleGenerator;
import Utils.Math.MathHelpers;
import Utils.Color.ColorHelpers;
import Scene.RaytracingInline;
import Scene.Scene;
import Scene.Shading;
import Experimental.Scene.Material.StandardMaterial;
import Experimental.Scene.Material.MaterialHelpers;

import ReSTIR;
import GBufferUtils;
import Helpers;

cbuffer CB
{
    uint2 gViewportDims;
    uint gFrameIndex;
    GBuffer gGBuffer;
}

static struct Data
{
    // Materials
    StandardMaterial standardMaterial;
} gData;

RWStructuredBuffer<Reservoir> gReservoirs;
RWTexture2D<float4> gShadingOutput;

[numthreads(16, 16, 1)]
void main(uint2 threadIndex : SV_DispatchThreadID, uint3 groupIndex: SV_GROUPID)
{
    if (any(threadIndex.xy >= gViewportDims)) 
    {
        return;
    }

    float3 res = 0.0;
    
    SampleGenerator sg = SampleGenerator.create(threadIndex, gFrameIndex);
    ShadingData sd;
    bool valid = PrepareRenderingData(gGBuffer, threadIndex, gScene.camera.getPosition(), sd);
    if (valid)
    {
        float bsdfPdf;
        float3 sampledDir = cosineWeightedSampling(sampleNext2D(sg), sd.N, bsdfPdf);
        res += gData.standardMaterial.eval(sd, sampledDir) / bsdfPdf;

        // RayDesc ray;
        // ray.Origin = rayData.origin;
        // ray.Direction = rayData.direction;
        // ray.TMin = 0.0f;
	    // ray.TMax = 1.0e38f;
        // if (!traceSceneVisibilityRay<1>(ray, RAY_FLAG_NONE, 0xff))
        // {
        //     float3 Le = gScene.envMap.eval(rayData.direction);
        //     res += rayData.thp * Le;
        // }
    }
    else
    {
        RayDesc ray = gScene.camera.computeRayPinhole(threadIndex, gViewportDims).toRayDesc();
        res += gScene.envMap.eval(ray.Direction);
    }

    // RayDesc ray = gScene.camera.computeRayPinhole(threadIndex, gViewportDims).toRayDesc();
    // if (!traceSceneVisibilityRay<1>(ray, RAY_FLAG_NONE, 0xff))
    // {
    //     res += float3(1.0, 0.0, 0.0);
    // }

    gShadingOutput[threadIndex] = float4(res, 1.0);
}
