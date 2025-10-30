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
        FastNoiseLite primaryNoise, FastNoiseLite secondaryNoise, FastNoiseLite heightNoise,
        Color[] colors, float[] thresholds,
        bool enableHeight, float heightInfluence, float heightVariation,
        float primaryWeight, float secondaryWeight, float contrast)
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

                float worldX = chunkWorldOrigin.X + localX;
                float worldZ = chunkWorldOrigin.Y + localZ;

                var pixelColor = GetPixelColor(worldX, worldZ,
                    primaryNoise, secondaryNoise, primaryWeight, secondaryWeight, 
                    contrast, colors, thresholds);

                var transform = Transform3D.Identity;
                transform.Origin = new Vector3(localX, 0, localZ);
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
    
    private static ArrayMesh CreateQuadMesh()
    {
        var vertices = new Vector3[]
        {
            new Vector3(-0.5f, 0, -0.5f), // Bottom-left
            new Vector3( 0.5f, 0, -0.5f), // Bottom-right
            new Vector3( 0.5f, 0,  0.5f), // Top-right
            new Vector3(-0.5f, 0,  0.5f)  // Top-left
        };

        var indices = new int[] { 0, 1, 2, 0, 2, 3 };
        var normals = new Vector3[] { Vector3.Up, Vector3.Up, Vector3.Up, Vector3.Up };
        var uvs = new Vector2[] { new Vector2(0, 1), new Vector2(1, 1), new Vector2(1, 0), new Vector2(0, 0) };

        var arrayMesh = new ArrayMesh();
        var arrays = new Godot.Collections.Array();
        arrays.Resize((int)Mesh.ArrayType.Max);

        arrays[(int)Mesh.ArrayType.Vertex] = vertices;
        arrays[(int)Mesh.ArrayType.Normal] = normals;
        arrays[(int)Mesh.ArrayType.TexUV] = uvs;
        arrays[(int)Mesh.ArrayType.Index] = indices;

        arrayMesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, arrays);
        return arrayMesh;
    }

    public void CreateMesh(int chunkSize, float pixelSize, StandardMaterial3D customMaterial)
    {
        if (Data.Transforms == null || Data.Transforms.Length == 0)
        {
            GD.PushError($"Chunk {ChunkCoord} has no instance data!");
            return;
        }

        if (Data.Colors == null || Data.Colors.Length != Data.Transforms.Length)
        {
            GD.PushError($"Chunk {ChunkCoord}: Colors array length mismatch!");
            return;
        }
        
        var baseMesh = CreateQuadMesh();
        var multiMesh = new MultiMesh();
        multiMesh.TransformFormat = MultiMesh.TransformFormatEnum.Transform3D;
        multiMesh.Mesh = baseMesh;
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