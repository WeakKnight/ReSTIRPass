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
    uint gInputBufferIndex;
    uint gOutputBufferIndex;
    ResamplingRuntimeParameters gParams;
    ShadingDataLoader gShadingDataLoader;
    EnvMapSampler gEnvMapSampler;
    EmissiveLightSampler gEmissiveLightSampler;
}

RWStructuredBuffer<Reservoir> gReservoirs;
Buffer<float2> gNeighborOffsetBuffer;

static struct Data
{
    StandardMaterial standardMaterial;
} gData;

static const uint numSamples = 4;
static const uint numDisocclusionBoostSamples = 4;
static const uint targetHistoryLength = 20;
static const float samplingRadius = 30.0f;
static const float positionThreshold = 1.0f;
static const float normalThreshold = 0.5f;
static const uint neighborOffsetMask = 8191;

[numthreads(16, 16, 1)]
void main(uint2 threadIndex : SV_DispatchThreadID, uint3 groupIndex: SV_GROUPID)
{
    if (any(threadIndex >= gViewportDims)) 
    {
        return;
    }

    SampleGenerator sg = SampleGenerator.create(threadIndex, gFrameIndex + 3 * 13);
    Reservoir spatialResult = emptyReservoir();
    ShadingData sd;
    bool valid = gShadingDataLoader.loadShadingData(threadIndex, gViewportDims, gScene.camera, sd);
    if (valid)
    {
        float3 posWOrigin = sd.computeNewRayOrigin();

        Reservoir centerSample = loadReservoir(gParams, gReservoirs, threadIndex, gInputBufferIndex);
        uint centerLightIndex = getReservoirLightIndex(centerSample);

        Reservoir state = emptyReservoir();

        int selected = -1;
        uint selectedLight;
        if (isValidReservoir(centerSample))
        {
            selectedLight = getReservoirLightIndex(centerSample);
        }

        combineReservoirs(state, centerSample, 0.5f, centerSample.targetPdf);

        int numSpatialSamples = numSamples;
        if (centerSample.M < targetHistoryLength)
        {
            numSpatialSamples = max(numSpatialSamples, numDisocclusionBoostSamples);
        }
        numSpatialSamples = min(numSpatialSamples, 32);

        uint startIdx = sampleNext1D(sg) * neighborOffsetMask;
        uint cachedResult = 0;
        for (uint i = 0; i < numSpatialSamples; i++)
        {
            uint sampleIdx = (startIdx + i) & neighborOffsetMask;
            int2 spatialOffset = int2(float2(gNeighborOffsetBuffer[sampleIdx].xy) * samplingRadius);
            int2 idx = threadIndex + spatialOffset;

            if (!isReprjTextureCoordValid(idx, gViewportDims))
            {
                continue;
            }

            ShadingData neighborSd;
            if (!gShadingDataLoader.loadShadingData(idx, gViewportDims, gScene.camera, neighborSd))
            {
                continue;
            }
            
            if (!isReprjNormalValid(sd.N, neighborSd.N, normalThreshold))
            {
                continue;
            }

            if (!isReprjPositionValid(sd.posW, neighborSd.posW, positionThreshold))
            {
                continue;
            }

            if (!areMaterialsSimilar(sd, neighborSd))
            {
                continue;
            }

            cachedResult |= (1u << uint(i));
            Reservoir neighborSample = loadReservoir(gParams, gReservoirs, idx, gInputBufferIndex);

            if (isValidReservoir(neighborSample))
            {
                uint lightIndex = getReservoirLightIndex(neighborSample);
                float2 lightUV = getReservoirSampleUV(neighborSample);
                float3 dir;
                float3 Le;
                if (lightIndex == EnvMapIndex)
                {
                    dir = gScene.envMap.toWorld(latlong_map_to_world(lightUV));
                    Le = gScene.envMap.eval(dir);
                }
                else
                {
                    EmissiveTriangle tri = gScene.lightCollection.getTriangle(lightIndex);
                    float3 barycentric = sample_triangle(lightUV);
                    float3 lightPos = tri.getPosition(barycentric);
                    float3 toLight = lightPos - posWOrigin; // Unnormalized light vector
                    const float distSqr = max(FLT_MIN, dot(toLight, toLight)); // Clamp to avoid NaNs below
                    float distance = sqrt(distSqr);
                    dir = toLight / distance;
                    float2 uv = tri.getTexCoord(barycentric);
                    Le = gScene.getEmissive(tri.materialID, uv, gScene.materialResources[tri.materialID]);
                }
                float targetPdf = luminance(Le * gData.standardMaterial.eval(sd, dir));;
                if (combineReservoirs(state, neighborSample, sampleNext1D(sg), targetPdf))
                {
                    selected = i;
                    selectedLight = lightIndex;
                }
            }
            else
            {
                state.M += neighborSample.M;
            }
        }

        if (isValidReservoir(state))
        {
            float pi = state.targetPdf;
            float piSum = state.targetPdf * centerSample.M;
            uint count = centerSample.M;
            for (uint i = 0; i < numSpatialSamples; i++)
            {
                if ((cachedResult & (1u << uint(i))) == 0) 
                {
                    continue;
                }
                uint sampleIdx = (startIdx + i) & neighborOffsetMask;
                int2 idx = threadIndex + int2(float2(gNeighborOffsetBuffer[sampleIdx].xy) * samplingRadius);
            
                ShadingData neighborSd;
                gShadingDataLoader.loadShadingData(idx, gViewportDims, gScene.camera, neighborSd);

                uint lightIndex = selectedLight;
                float2 lightUV = getReservoirSampleUV(state);
                float3 dir;
                float3 Le;
                if (lightIndex == EnvMapIndex)
                {
                    dir = gScene.envMap.toWorld(latlong_map_to_world(lightUV));
                    Le = gScene.envMap.eval(dir);
                }
                else
                {
                    EmissiveTriangle tri = gScene.lightCollection.getTriangle(lightIndex);
                    float3 barycentric = sample_triangle(lightUV);
                    float3 lightPos = tri.getPosition(barycentric);
                    float3 toLight = lightPos - posWOrigin; // Unnormalized light vector
                    const float distSqr = max(FLT_MIN, dot(toLight, toLight)); // Clamp to avoid NaNs below
                    float distance = sqrt(distSqr);
                    dir = toLight / distance;
                    float2 uv = tri.getTexCoord(barycentric);
                    Le = gScene.getEmissive(tri.materialID, uv, gScene.materialResources[tri.materialID]);
                }
                float targetPdf = luminance(Le * gData.standardMaterial.eval(neighborSd, dir));;
                float ps = targetPdf;
                
                Reservoir neighborSample = loadReservoir(gParams, gReservoirs, idx, gInputBufferIndex);
                if (ps > 0)
                {
                    count += neighborSample.M;
                }

                pi = (selected == i ? ps : pi);
                piSum += ps * neighborSample.M;
            }
            finalizeResampling(state, pi, piSum);
        }
        else
        {
            finalizeResampling(state, 1.f, state.M);
        }

        spatialResult = state;
    }

    storeReservoir(gParams, spatialResult, gReservoirs, threadIndex, gOutputBufferIndex);
}