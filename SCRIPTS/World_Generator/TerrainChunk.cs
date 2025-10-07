using Godot;
using System;
using System.IO;
using System.Collections.Generic;
using GodotFileAccess = Godot.FileAccess;
using System.Linq;

public partial class TerrainChunk
{
    public Vector2I ChunkCoord { get; private set; }
    public MultiMeshInstance3D MultiMeshInstance { get; private set; }
    public ChunkData Data { get; private set; }
    public bool IsDirty { get; set; }

    public TerrainChunk(Vector2I coord, ChunkData data)
    {
        ChunkCoord = coord;
        Data = data;
        IsDirty = data.IsDirty;
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
            ChunkCoord = chunkCoord,
            IsDirty = true
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

        // Use custom material if provided, otherwise create default
        StandardMaterial3D material;
        if (customMaterial != null)
        {
            // Duplicate the custom material so each chunk can have independent settings
            material = (StandardMaterial3D)customMaterial.Duplicate();
            
            // Ensure critical color settings are correct even with custom material
            material.VertexColorUseAsAlbedo = true;
            
            // CRITICAL FIX: Try false first for vibrant colors
            material.VertexColorIsSrgb = true;
        }
        else
        {
            // Create default material with proper color handling
            material = new StandardMaterial3D();
            
            // Core settings for proper color display
            material.ShadingMode = BaseMaterial3D.ShadingModeEnum.PerPixel;
            material.VertexColorUseAsAlbedo = true;
            material.AlbedoColor = Colors.White;  // WHITE to not darken instance colors
            
            // CRITICAL FIX: Set to false for vibrant colors (try true if colors still wrong)
            material.VertexColorIsSrgb = false;
            
            // Material properties
            material.Roughness = 0.8f;
            material.Metallic = 0.0f;
            
            // Pixelated aesthetic
            material.TextureFilter = BaseMaterial3D.TextureFilterEnum.Nearest;
            
            // Rendering settings
            material.CullMode = BaseMaterial3D.CullModeEnum.Back;
        }

        MultiMeshInstance.MaterialOverride = material;
        MultiMeshInstance.CastShadow = GeometryInstance3D.ShadowCastingSetting.On;
        MultiMeshInstance.GIMode = GeometryInstance3D.GIModeEnum.Disabled;
    }
    #endregion

    #region Caching (Thread-Safe Serialization/Deserialization)

    private static string GetFilePath(Vector2I coord, string savePath)
    {
        var resolvedPath = savePath.Replace("res://", "");
        var fullPath = $"user://{resolvedPath}";
        return System.IO.Path.Combine(fullPath, $"chunk_{coord.X}_{coord.Y}.chunk");
    }

    public void SaveToFile(string path)
    {
        if (!IsDirty) return;

        try
        {
            var filePath = GetFilePath(ChunkCoord, path);
            
            using var file = GodotFileAccess.Open(filePath, GodotFileAccess.ModeFlags.Write);
            if (file != null)
            {
                var saveData = new Godot.Collections.Dictionary
                {
                    ["t"] = SerializeTransformArray(Data.Transforms),
                    ["c"] = SerializeColorArray(Data.Colors)
                };
                
                file.StoreVar(saveData);
                IsDirty = false;
            }
            else
            {
                GD.PushError($"Failed to open file for saving chunk {ChunkCoord}: {GodotFileAccess.GetOpenError()}");
            }
        }
        catch (Exception ex)
        {
            GD.PushError($"Failed to save chunk {ChunkCoord}: {ex.Message}");
        }
    }

    public static ChunkData LoadFromFile(Vector2I chunkCoord, string path)
    {
        var filePath = GetFilePath(chunkCoord, path);

        if (!GodotFileAccess.FileExists(filePath))
            return null;

        try
        {
            using var file = GodotFileAccess.Open(filePath, GodotFileAccess.ModeFlags.Read);
            if (file != null)
            {
                var loadedData = file.GetVar().AsGodotDictionary();
                
                var transforms = DeserializeTransformArray((byte[])loadedData["t"]);
                var colors = DeserializeColorArray((byte[])loadedData["c"]);
                
                if (transforms.Length != colors.Length)
                {
                    GD.PushWarning($"LoadFromFile {chunkCoord}: Array length mismatch! Will regenerate.");
                    return null;
                }

                return new ChunkData
                {
                    Transforms = transforms,
                    Colors = colors,
                    ChunkCoord = chunkCoord,
                    IsDirty = false
                };
            }
        }
        catch (Exception ex)
        {
            GD.PushWarning($"Failed to load chunk {chunkCoord}: {ex.Message}. Will regenerate.");
        }

        return null;
    }

    private static byte[] SerializeTransformArray(Transform3D[] array)
    {
        var bytes = new byte[array.Length * 48];
        for (int i = 0; i < array.Length; i++)
        {
            var t = array[i];
            int offset = i * 48;
            Buffer.BlockCopy(BitConverter.GetBytes(t.Basis.X.X), 0, bytes, offset, 4);
            Buffer.BlockCopy(BitConverter.GetBytes(t.Basis.X.Y), 0, bytes, offset + 4, 4);
            Buffer.BlockCopy(BitConverter.GetBytes(t.Basis.X.Z), 0, bytes, offset + 8, 4);
            Buffer.BlockCopy(BitConverter.GetBytes(t.Basis.Y.X), 0, bytes, offset + 12, 4);
            Buffer.BlockCopy(BitConverter.GetBytes(t.Basis.Y.Y), 0, bytes, offset + 16, 4);
            Buffer.BlockCopy(BitConverter.GetBytes(t.Basis.Y.Z), 0, bytes, offset + 20, 4);
            Buffer.BlockCopy(BitConverter.GetBytes(t.Basis.Z.X), 0, bytes, offset + 24, 4);
            Buffer.BlockCopy(BitConverter.GetBytes(t.Basis.Z.Y), 0, bytes, offset + 28, 4);
            Buffer.BlockCopy(BitConverter.GetBytes(t.Basis.Z.Z), 0, bytes, offset + 32, 4);
            Buffer.BlockCopy(BitConverter.GetBytes(t.Origin.X), 0, bytes, offset + 36, 4);
            Buffer.BlockCopy(BitConverter.GetBytes(t.Origin.Y), 0, bytes, offset + 40, 4);
            Buffer.BlockCopy(BitConverter.GetBytes(t.Origin.Z), 0, bytes, offset + 44, 4);
        }
        return bytes;
    }

    private static Transform3D[] DeserializeTransformArray(byte[] bytes)
    {
        var array = new Transform3D[bytes.Length / 48];
        for (int i = 0; i < array.Length; i++)
        {
            int offset = i * 48;
            var basis = new Basis(
                new Vector3(BitConverter.ToSingle(bytes, offset), BitConverter.ToSingle(bytes, offset + 4), BitConverter.ToSingle(bytes, offset + 8)),
                new Vector3(BitConverter.ToSingle(bytes, offset + 12), BitConverter.ToSingle(bytes, offset + 16), BitConverter.ToSingle(bytes, offset + 20)),
                new Vector3(BitConverter.ToSingle(bytes, offset + 24), BitConverter.ToSingle(bytes, offset + 28), BitConverter.ToSingle(bytes, offset + 32))
            );
            var origin = new Vector3(BitConverter.ToSingle(bytes, offset + 36), BitConverter.ToSingle(bytes, offset + 40), BitConverter.ToSingle(bytes, offset + 44));
            array[i] = new Transform3D(basis, origin);
        }
        return array;
    }

    private static byte[] SerializeColorArray(Color[] array)
    {
        var bytes = new byte[array.Length * 16];
        for (int i = 0; i < array.Length; i++)
        {
            Buffer.BlockCopy(BitConverter.GetBytes(array[i].R), 0, bytes, i * 16, 4);
            Buffer.BlockCopy(BitConverter.GetBytes(array[i].G), 0, bytes, i * 16 + 4, 4);
            Buffer.BlockCopy(BitConverter.GetBytes(array[i].B), 0, bytes, i * 16 + 8, 4);
            Buffer.BlockCopy(BitConverter.GetBytes(array[i].A), 0, bytes, i * 16 + 12, 4);
        }
        return bytes;
    }

    private static Color[] DeserializeColorArray(byte[] bytes)
    {
        var array = new Color[bytes.Length / 16];
        for (int i = 0; i < array.Length; i++)
        {
            array[i] = new Color(
                BitConverter.ToSingle(bytes, i * 16),
                BitConverter.ToSingle(bytes, i * 16 + 4),
                BitConverter.ToSingle(bytes, i * 16 + 8),
                BitConverter.ToSingle(bytes, i * 16 + 12)
            );
        }
        return array;
    }
    #endregion
}