#include "Utils/Math/MathConstants.slangh"
import Utils.Sampling.SampleGenerator;
import Utils.Math.MathHelpers;
import Utils.Color.ColorHelpers;
import Scene.RaytracingInline;
import Scene.Scene;
import Scene.Shading;
import Experimental.Scene.Material.StandardMaterial;
import Experimental.Scene.Material.MaterialHelpers;
import Experimental.Scene.Lights.EnvMapSampler;
import Experimental.Scene.Lights.EmissiveLightSampler;

import ReSTIR;
import ShadingDataLoader;
import Helpers;

cbuffer CB
{
    uint2 gViewportDims;
    uint gFrameIndex;
    uint gOutputBufferIndex;
    ResamplingRuntimeParameters gParams;
    ShadingDataLoader gShadingDataLoader;
    EnvMapSampler gEnvMapSampler;
    EmissiveLightSampler gEmissiveLightSampler;
}

RWStructuredBuffer<Reservoir> gReservoirs;

static struct Data
{
    StandardMaterial standardMaterial;
} gData;

[numthreads(16, 16, 1)]
void main(uint2 threadIndex : SV_DispatchThreadID, uint3 groupIndex: SV_GROUPID)
{
    if (any(threadIndex >= gViewportDims)) 
    {
        return;
    }

    SampleGenerator sg = SampleGenerator.create(threadIndex, gFrameIndex + 1 * 13);
    Reservoir r = emptyReservoir();

    ShadingData sd;
    bool valid = gShadingDataLoader.loadShadingData(threadIndex, gViewportDims, gScene.camera, sd);
    if (valid)
    {
        float3 posWOrigin = sd.computeNewRayOrigin();

        Reservoir triangleLightReservoir = emptyReservoir();
        for (uint i = 0; i < _INITIAL_EMISSIVE_TRIANGLE_SAMPLES; i++);
        {
            TriangleLightSample lightSample;
            if (gEmissiveLightSampler.sampleLight(posWOrigin, sd.N, true, sg, lightSample) && dot(sd.N, lightSample.dir) >= kMinCosTheta)
            {
                float invPdf = 1.0f / lightSample.pdf;
                float targetPdf = luminance(lightSample.Le * gData.standardMaterial.eval(sd, lightSample.dir));
                streamSample(triangleLightReservoir, lightSample.triangleIndex, lightSample.uv, sampleNext1D(sg), targetPdf, invPdf);
            }
            else
            {
                triangleLightReservoir.M += 1;
            }
        }
        finalizeResampling(triangleLightReservoir, 1.0, triangleLightReservoir.M);
        triangleLightReservoir.M = 1;

        Reservoir envMapReservoir = emptyReservoir();
        for(uint i = 0; i < _INITIAL_ENVMAP_SAMPLES; i++)
        {
            EnvMapSample envMapSample;
            if (gEnvMapSampler.sample(sampleNext2D(sg), envMapSample))
            {
                float invPdf = 1.0f / envMapSample.pdf;
                float targetPdf = luminance(envMapSample.Le * gData.standardMaterial.eval(sd, envMapSample.dir));
                float2 uv = world_to_latlong_map(gScene.envMap.toLocal(envMapSample.dir));
                streamSample(envMapReservoir, EnvMapIndex, uv, sampleNext1D(sg), targetPdf, invPdf);
            }
            else
            {
                envMapReservoir.M += 1;
            }
        }
        finalizeResampling(envMapReservoir, 1.0, envMapReservoir.M);
        envMapReservoir.M = 1;

        combineReservoirs(r, triangleLightReservoir, sampleNext1D(sg), triangleLightReservoir.targetPdf);
        combineReservoirs(r, envMapReservoir, sampleNext1D(sg), envMapReservoir.targetPdf);
        finalizeResampling(r, 1.0, 1.0);
        r.M = 1;        

        if (isValidReservoir(r))
        {
            uint lightIndex = getReservoirLightIndex(r);
            float2 lightUV = getReservoirSampleUV(r);

            RayDesc ray;
            ray.Origin = posWOrigin;
            ray.TMin = 0.001f;
            if (lightIndex == EnvMapIndex)
            {
                ray.Direction = gScene.envMap.toWorld(latlong_map_to_world(lightUV));
                ray.TMax = 1.0e38f;
            }
            else
            {
                EmissiveTriangle tri = gScene.lightCollection.getTriangle(lightIndex);
                float3 lightPos = tri.getPosition(sample_triangle(lightUV));
                float3 toLight = lightPos - posWOrigin; // Unnormalized light vector
                const float distSqr = max(FLT_MIN, dot(toLight, toLight)); // Clamp to avoid NaNs below
                float distance = sqrt(distSqr);
                ray.Direction = toLight / distance;
                ray.TMax = distance - 0.001f;
            }

            if (!traceSceneVisibilityRay<1>(ray, RAY_FLAG_NONE, 0xff))
            {
                r.lightData = 0;
                r.weightSum = 0;
            }
        }
    }

    storeReservoir(gParams, r, gReservoirs, threadIndex, gOutputBufferIndex);
}
