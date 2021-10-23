import Scene.Scene;
import Scene.Shading;
import Scene.HitInfo;
import Utils.Math.MathHelpers;
import Experimental.Scene.Material.MaterialHelpers;

struct ShadingDataLoader
{
    Texture2D<float4> worldPosition;
    Texture2D<float4> worldShadingNormal;
    Texture2D<float4> worldFaceNormal;
    Texture2D<float4> materialDiffuseOpacity;
    Texture2D<float4> materialSpecularRoughness;
    Texture2D<float4> materialEmissive;
    Texture2D<float4> materialExtraParams;

    /** Returns the primary ray's direction.
    */
    float3 getPrimaryRayDir(uint2 pixel, uint2 frameDim, const Camera camera)
    {
        // Compute the view vector. This must exactly match what the G-buffer pass is doing (jitter etc.).
        // Note that we do not take depth-of-field into account as it would require exactly matching the
        // sample generator between the passes, which is error prone. The host side will issue a warning instead.
        return camera.computeRayPinhole(pixel, frameDim).dir;
    }

    /** Helper for setting up the ShadingData struct based on loaded data.
        \param[in] pixel Current pixel coordinates.
        \param[in] frameDim Frame dimensions in pixel.
        \param[in] camera Current camera.
        \param[out] sd ShadingData struct.
        \param[out] hit HitInfo struct returned with geometry fetched from vbuffer if available. Only valid if true is returned.
        \return True if the pixel has valid data (not a background pixel). Note sd.V is always valid.
    */
    bool loadShadingData(uint2 pixel, uint2 frameDim, const Camera camera, out ShadingData sd)
    {
        sd = {};

        float3 rayDir = getPrimaryRayDir(pixel, frameDim, camera);
        bool valid = false;

        float4 worldPos = worldPosition[pixel];
        if (worldPos.w != 0.f) // Using w to indicate valid geometry for now.
        {
            // Load geometry and material parameters from G-buffer.
            float3 normal = worldShadingNormal[pixel].xyz;
            float4 tangent = float4(perp_stark(normal), 1.f);
            float3 faceNormal = worldFaceNormal[pixel].xyz;
            GeometryParams geoParams = prepareGeometryParams(worldPos.xyz, -rayDir, normal, tangent, faceNormal);

            MaterialParams matParams;
            matParams.diffuseOpacity = materialDiffuseOpacity[pixel];
            matParams.specularRoughness = materialSpecularRoughness[pixel];
            matParams.emissive = materialEmissive[pixel];
            matParams.extraParams = materialExtraParams[pixel];

            sd = prepareShadingData(geoParams, matParams);
            valid = true;
        }

        sd.V = -rayDir;
        return valid;
    }
};