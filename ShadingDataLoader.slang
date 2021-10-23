import Scene.Scene;
import Scene.Shading;
import Scene.HitInfo;
import Utils.Math.MathHelpers;
import Experimental.Scene.Material.MaterialHelpers;

struct ShadingDataLoader
{
    Texture2D<PackedHitInfo> VBuffer;
    Texture2D<PackedHitInfo> VBufferPrev;
    Texture2D<float2> motionVector;

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
    bool loadShadingData(uint2 pixel, uint2 frameDim, const Camera camera, Texture2D<PackedHitInfo> VBufferTex, out ShadingData sd)
    {
        sd = {};

        float3 rayDir = getPrimaryRayDir(pixel, frameDim, camera);
        bool valid = false;

        HitInfo hit;
        hit = HitInfo(VBufferTex[pixel]);
        if (hit.isValid() && hit.getType() == HitType::Triangle)
        {
            const TriangleHit triangleHit = hit.getTriangleHit();
            // Evaluate Falcor's material parameters at the hit point.
            // TODO: Implement texLOD to enable texture filtering in prepareShadingData().
            const VertexData v = gScene.getVertexData(triangleHit);
            const uint materialID = gScene.getMaterialID(triangleHit.instanceID);
            sd = prepareShadingData(v, materialID, gScene.materials[materialID], gScene.materialResources[materialID], -rayDir, 0.f);

            // Adjust shading normals if GBuffer pass has flag enabled.
            adjustShadingNormal(sd, v);
            valid = true;
        }

        sd.V = -rayDir;
        return valid;
    }

    bool loadShadingData(uint2 pixel, uint2 frameDim, const Camera camera, out ShadingData sd)
    {
        return loadShadingData(pixel, frameDim, camera, VBuffer, sd);
    }

    bool loadShadingDataPrevFrame(uint2 pixel, uint2 frameDim, const Camera camera, out ShadingData sd)
    {
        return loadShadingData(pixel, frameDim, camera, VBufferPrev, sd);
    }
};