using Godot;
using System;
using System.Collections.Generic;

public partial class TerrainChunk
{
    public Vector2I ChunkCoord { get; private set; }
    public MultiMeshInstance3D MultiMeshInstance { get; private set; }
    public ChunkData Data { get; private set; }

    public TerrainChunk(Vector2I coord, ChunkData data)
    {
        ChunkCoord = coord;
        Data = data;
        MultiMeshInstance = new MultiMeshInstance3D
        {
            Name = $"chunk_{coord}"
        };
    }

    #region Generation (Thread-Safe)

    public static ChunkData Generate(
        Vector2I chunkCoord, int chunkSize, float pixelSize,
        FastNoiseLite primaryNoise, FastNoiseLite secondaryNoise, FastNoiseLite heightNoise, FastNoiseLite waterNoise, FastNoiseLite beachNoise,
        Color[] colors, float[] thresholds,
        bool enableHeight, float heightInfluence, float heightVariation,
        float primaryWeight, float secondaryWeight, float contrast,
        bool enableWater, float waterThreshold, Color waterColor, float waterHeight,
        bool enableBeaches, float beachThreshold, float beachWidth, Color sandColor)
    {
        var chunkWorldSize = chunkSize * pixelSize;
        var chunkWorldOrigin = new Vector2(chunkCoord.X * chunkWorldSize, chunkCoord.Y * chunkWorldSize);
        float halfChunkWorldSize = chunkWorldSize * 0.5f;

        var transforms = new List<Transform3D>();
        var instanceColors = new List<Color>();

        for (int z = 0; z < chunkSize; z++)
        {
            for (int x = 0; x < chunkSize; x++)
            {
                float localX = (x * pixelSize) - halfChunkWorldSize + (pixelSize * 0.5f);
                float localZ = (z * pixelSize) - halfChunkWorldSize + (pixelSize * 0.5f);

                float worldX = (chunkWorldOrigin.X + halfChunkWorldSize) + localX;
                float worldZ = (chunkWorldOrigin.Y + halfChunkWorldSize) + localZ;

                // Check if this pixel is water - if so, skip it (water is now handled separately)
                bool isWater = false;
                if (enableWater && waterNoise != null)
                {
                    float waterValue = waterNoise.GetNoise2D(worldX, worldZ);
                    isWater = waterValue < waterThreshold;
                }

                // Skip water pixels entirely - they're handled by WaterChunk now
                if (isWater)
                {
                    continue;
                }

                // Check for beaches
                bool isBeach = false;
                if (enableBeaches && beachNoise != null && enableWater && waterNoise != null)
                {
                    bool hasWaterNearby = false;
                    float checkRadius = beachWidth * pixelSize;
                    for (float angle = 0; angle < Mathf.Tau; angle += Mathf.Tau / 8)
                    {
                        float checkX = worldX + Mathf.Cos(angle) * checkRadius;
                        float checkZ = worldZ + Mathf.Sin(angle) * checkRadius;
                        
                        float checkWaterValue = waterNoise.GetNoise2D(checkX, checkZ);
                        if (checkWaterValue < waterThreshold)
                        {
                            hasWaterNearby = true;
                            break;
                        }
                    }
                    
                    if (hasWaterNearby)
                    {
                        float beachNoiseValue = beachNoise.GetNoise2D(worldX, worldZ);
                        if (beachNoiseValue > beachThreshold && Mathf.Abs(waterHeight) < beachWidth)
                        {
                            isBeach = true;
                        }
                    }
                }
                
                // Determine pixel color
                Color pixelColor;
                if (isBeach)
                {
                    pixelColor = sandColor;
                }
                else
                {
                    pixelColor = GetPixelColor(worldX, worldZ,
                        primaryNoise, secondaryNoise, primaryWeight, secondaryWeight, 
                        contrast, colors, thresholds);
                }
                
                // Calculate height
                float yPosition = 0.0f;
                if (enableHeight && heightNoise != null)
                {
                    float heightValue = heightNoise.GetNoise2D(worldX, worldZ);
                    yPosition += heightValue * heightVariation * heightInfluence;
                }

                // Create transform
                var transform = Transform3D.Identity;
                transform.Origin = new Vector3(localX, yPosition, localZ);
                transform = transform.Scaled(new Vector3(pixelSize, 1.0f, pixelSize));

                transforms.Add(transform);
                instanceColors.Add(pixelColor);
            }
        }

        return new ChunkData
        {
            Transforms = transforms.ToArray(),
            Colors = instanceColors.ToArray(),
            ChunkCoord = chunkCoord
        };
    }

    private static Color GetPixelColor(float wx, float wz, 
        FastNoiseLite pNoise, FastNoiseLite sNoise,
        float pWeight, float sWeight, float contrast,
        Color[] colors, float[] thresholds)
    {
        float pVal = pNoise.GetNoise2D(wx, wz);
        float sVal = sNoise.GetNoise2D(wx, wz);
        float combined = Mathf.Clamp((pVal * pWeight + sVal * sWeight) * contrast, -1.0f, 1.0f);

        for (int i = 0; i < thresholds.Length; i++)
        {
            if (combined < thresholds[i])
                return colors[i];
        }

        return colors[^1];
    }
    #endregion

    #region Mesh Creation (Main Thread)
    
    public void CreateMesh(int chunkSize, float pixelSize, StandardMaterial3D customMaterial, ArrayMesh pixelMesh)
    {
        if (Data.Transforms == null || Data.Transforms.Length == 0)
        {
            return;
        }

        if (Data.Colors == null || Data.Colors.Length != Data.Transforms.Length)
        {
            GD.PushError($"Chunk {ChunkCoord}: Colors array length mismatch!");
            return;
        }
        
        var multiMesh = new MultiMesh();
        multiMesh.TransformFormat = MultiMesh.TransformFormatEnum.Transform3D;
        multiMesh.Mesh = pixelMesh;
        multiMesh.UseColors = true;
        multiMesh.InstanceCount = Data.Transforms.Length;

        for (int i = 0; i < Data.Transforms.Length; i++)
        {
            multiMesh.SetInstanceTransform(i, Data.Transforms[i]);
            multiMesh.SetInstanceColor(i, Data.Colors[i]);
        }

        MultiMeshInstance.Multimesh = multiMesh;

        StandardMaterial3D material;
        if (customMaterial != null)
        {
            material = (StandardMaterial3D)customMaterial.Duplicate();
            material.VertexColorUseAsAlbedo = true;
            material.VertexColorIsSrgb = true;
        }
        else
        {
            material = new StandardMaterial3D();
            material.ShadingMode = BaseMaterial3D.ShadingModeEnum.PerPixel;
            material.VertexColorUseAsAlbedo = true;
            material.AlbedoColor = Colors.White;
            material.VertexColorIsSrgb = false;
            material.Roughness = 0.8f;
            material.Metallic = 0.0f;
            material.TextureFilter = BaseMaterial3D.TextureFilterEnum.Nearest;
            material.CullMode = BaseMaterial3D.CullModeEnum.Back;
        }

        MultiMeshInstance.MaterialOverride = material;
        MultiMeshInstance.CastShadow = GeometryInstance3D.ShadowCastingSetting.On;
        MultiMeshInstance.GIMode = GeometryInstance3D.GIModeEnum.Disabled;
    }
    #endregion
}