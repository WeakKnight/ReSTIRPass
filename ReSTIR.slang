#include "Utils/Math/MathConstants.slangh"
import Utils.Sampling.SampleGenerator;

static const uint EnvMapIndex = 0x7FFFFFFF; 

struct ResamplingRuntimeParameters
{
    uint reservoirBlockRowPitch;
    uint reservoirArrayPitch;
};

struct Reservoir
{
    // Light index (bits 0..30) and validity bit (31)
    uint lightData;

    // Sample UV encoded in 16-bit fixed point format
    uint uvData;

    // Overloaded: represents RIS weight sum during streaming,
    // then reservoir weight (inverse PDF) after FinalizeResampling
    float weightSum;

    // Target PDF of the selected sample
    float targetPdf;

    // Number of samples considered for this reservoir
    uint M;

    // Light index helpers
    static const uint c_MaxM = 0x3fff;
    static const uint c_LightValidBit = 0x80000000;
    static const uint c_LightIndexMask = 0x7FFFFFFF;
};

uint reservoirPositionToPointer(
    ResamplingRuntimeParameters params,
    uint2 reservoirPosition,
    uint reservoirArrayIndex,
    )
{
    uint2 blockIdx = reservoirPosition / 16;
    uint2 positionInBlock = reservoirPosition % 16;

    return reservoirArrayIndex * params.reservoirArrayPitch
        + blockIdx.y * params.reservoirBlockRowPitch
        + blockIdx.x * (16 * 16)
        + positionInBlock.y * 16
        + positionInBlock.x;
}

void storeReservoir(
    ResamplingRuntimeParameters params,
    const Reservoir reservoir,
    RWStructuredBuffer<Reservoir> LightReservoirs,
    uint2 reservoirPosition,
    uint reservoirArrayIndex)
{
    uint pointer = reservoirPositionToPointer(params, reservoirPosition, reservoirArrayIndex);
    LightReservoirs[pointer] = reservoir;
}

Reservoir loadReservoir(
    ResamplingRuntimeParameters params,
    RWStructuredBuffer<Reservoir> LightReservoirs,
    uint2 reservoirPosition,
    uint reservoirArrayIndex)
{
    uint pointer = reservoirPositionToPointer(params, reservoirPosition, reservoirArrayIndex);
    return LightReservoirs[pointer];
}

Reservoir emptyReservoir()
{
    Reservoir s;
    s.lightData = 0;
    s.uvData = 0;
    s.targetPdf = 0;
    s.weightSum = 0;
    s.M = 0;
    return s;
}

bool isValidReservoir(const Reservoir reservoir)
{
    return reservoir.lightData != 0;
}

uint getReservoirLightIndex(const Reservoir reservoir)
{
    return reservoir.lightData & Reservoir::c_LightIndexMask;
}

uint packUV(float2 uv)
{
    return uint(saturate(uv.x) * 0xffff) | (uint(saturate(uv.y) * 0xffff) << 16);
}

float2 unpackUV(uint uvData)
{
    return float2(uvData & 0xffff, uvData >> 16) / float(0xffff);
}

float2 getReservoirSampleUV(const Reservoir reservoir)
{
    return unpackUV(reservoir.uvData);
}

float getReservoirInvPdf(const Reservoir reservoir)
{
    return reservoir.weightSum;
}

// Adds a new, non-reservoir light sample into the reservoir, returns true if this sample was selected.
// Algorithm (3) from the ReSTIR paper, Streaming RIS using weighted reservoir sampling.
bool streamSample(
    inout Reservoir reservoir,
    uint lightIndex,
    float2 uv,
    float random,
    float targetPdf,
    float invSourcePdf)
{
    // What's the current weight
    float risWeight = targetPdf * invSourcePdf;

    // Add one sample to the counter
    reservoir.M += 1;

    // Update the weight sum
    reservoir.weightSum += risWeight;

    // Decide if we will randomly pick this sample
    bool selectSample = (random * reservoir.weightSum < risWeight);

    // If we did select this sample, update the relevant data.
    // New samples don't have visibility or age information, we can skip that.
    if (selectSample) 
    {
        reservoir.lightData = lightIndex | Reservoir::c_LightValidBit;
        reservoir.uvData = packUV(uv);
        reservoir.targetPdf = targetPdf;
    }

    return selectSample;
}

// Adds `newReservoir` into `reservoir`, returns true if the new reservoir's sample was selected.
// Algorithm (4) from the ReSTIR paper, Combining the streams of multiple reservoirs.
// Normalization - Equation (6) - is postponed until all reservoirs are combined.
bool combineReservoirs(
    inout Reservoir reservoir,
    const Reservoir newReservoir,
    float random,
    float targetPdf,
    float misWeight = 1.f)
{
    // What's the current weight (times any prior-step RIS normalization factor)
    float risWeight = targetPdf * newReservoir.weightSum * newReservoir.M * misWeight;

    // Our *effective* candidate pool is the sum of our candidates plus those of our neighbors
    reservoir.M += newReservoir.M;

    // Update the weight sum
    reservoir.weightSum += risWeight;

    // Decide if we will randomly pick this sample
    bool selectSample = (random * reservoir.weightSum < risWeight);

    // If we did select this sample, update the relevant data
    if (selectSample) 
    {
        reservoir.lightData = newReservoir.lightData;
        reservoir.uvData = newReservoir.uvData;
        reservoir.targetPdf = targetPdf;
    }

    return selectSample;
}

// Performs normalization of the reservoir after streaming. Equation (6) from the ReSTIR paper.
void finalizeResampling(
    inout Reservoir reservoir,
    float normalizationNumerator,
    float normalizationDenominator)
{
    float denominator = reservoir.targetPdf * normalizationDenominator;

    reservoir.weightSum = (denominator == 0.0) ? 0.0 : (reservoir.weightSum * normalizationNumerator) / denominator;
}
