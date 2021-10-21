#include "Utils/Math/MathConstants.slangh"
import Utils.Sampling.SampleGenerator;
import Utils.Math.MathHelpers;
import Utils.Color.ColorHelpers;
import Scene.RaytracingInline;
import Scene.Scene;
import Scene.Shading;

import ReSTIR;
import GBufferUtils;
import Helpers;

cbuffer CB
{
    uint2 gViewportDims;
    uint gFrameIndex;
    GBuffer gGBuffer;
}

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
    bool valid = PrepareRenderingData(gGBuffer, threadIndex.xy, gScene.camera.getPosition(), sd);
    if (valid)
    {
        res = sd.diffuse;
    }

    gShadingOutput[threadIndex] = float4(res, 1.0);
}
