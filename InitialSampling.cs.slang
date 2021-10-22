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
    ResamplingRuntimeParameters gParams;
    GBuffer gGBuffer;
    uint gOutputBufferIndex;
}

RWStructuredBuffer<Reservoir> gReservoirs;

static struct Data
{
    StandardMaterial standardMaterial;
} gData;

[numthreads(16, 16, 1)]
void main(uint2 threadIndex : SV_DispatchThreadID, uint3 groupIndex: SV_GROUPID)
{
    if (any(threadIndex.xy >= gViewportDims)) 
    {
        return;
    }

    SampleGenerator sg = SampleGenerator.create(threadIndex, gFrameIndex + 1 * 13);
    Reservoir r = emptyReservoir();

    ShadingData sd;
    bool valid = PrepareRenderingData(gGBuffer, threadIndex.xy, gScene.camera.getPosition(), sd);
    if (valid)
    {
        for(uint i = 0; i < 8; i++)
        {
            uint lightIndex = gFluxTable.sample(sampleNext2D(sg));
            float lightInvPdf = gFluxTable.weightSum / gFluxTable.getWeight(lightIndex);

            float2 VSLrand = sampleNext2D(sg);
            float ConePdf = 1.f;
            float3 ConeDir = 0.f;
            float targetPdf = luminance(gVirtualLights.coneComputeShadingPointRadianceForVPL(sd, sg, lightIndex));
            float MISTotalProb = numInitialSamples * ConePdf;
            if (streamSample(r, lightIndex, VSLrand, sampleNext1D(sg), targetPdf, lightInvPdf / MISTotalProb))
            {
                selectedLPdf = ConePdf;
            }
        }

        if (isValidReservoir(r))
        {
            float3 rayOrigin = computeRayOrigin(sd.posW, sd.frontFacing ? sd.faceN : -sd.faceN);
            uint lightIndex = getReservoirLightIndex(r);
            float3 lightPos = gVirtualLights.getPosition(lightIndex);

            if (isOccluded(rayOrigin, lightPos))
            {
                r.lightData = 0;
                r.weightSum = 0;
            }
        }

        r.targetPdf /= selectedLPdf; // convert to primary sample space (assuming cone sampling technique) for reusing random numbers

        r.M = 1;
        finalizeResampling(r, 1.0, r.M);
    }

    storeReservoir(gParams, r, gReservoirs, threadIndex.xy, gOutputBufferIndex);
}
