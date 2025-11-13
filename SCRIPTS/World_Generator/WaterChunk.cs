using Godot;
using System;

public partial class WaterChunk
{
    public Vector2I ChunkCoord { get; private set; }
    public MeshInstance3D WaterMesh { get; private set; }
    
    private StandardMaterial3D _chunkWaterMaterial;
    
    public WaterChunk(Vector2I coord)
    {
        ChunkCoord = coord;
        WaterMesh = new MeshInstance3D
        {
            Name = $"water_chunk_{coord}"
        };
    }

    public static WaterChunkData GenerateWaterChunk(
        Vector2I chunkCoord, 
        int chunkSize, 
        float pixelSize,
        FastNoiseLite waterNoise,
        float waterThreshold,
        float waterHeight)
    {
        var chunkWorldSize = chunkSize * pixelSize;
        var chunkWorldOrigin = new Vector2(chunkCoord.X * chunkWorldSize, chunkCoord.Y * chunkWorldSize);

        bool hasWater = false;
        int waterPixelCount = 0;
        
        var maskData = new bool[chunkSize, chunkSize];

        for (int z = 0; z < chunkSize; z++)
        {
            for (int x = 0; x < chunkSize; x++)
            {
                float worldX = chunkWorldOrigin.X + (x * pixelSize) + (pixelSize * 0.5f);
                float worldZ = chunkWorldOrigin.Y + (z * pixelSize) + (pixelSize * 0.5f);
                
                if (waterNoise != null)
                {
                    float waterValue = waterNoise.GetNoise2D(worldX, worldZ);
                    bool isWater = waterValue < waterThreshold;
                    maskData[x, z] = isWater;
                    
                    if (isWater)
                    {
                        hasWater = true;
                        waterPixelCount++;
                    }
                }
            }
        }

        float waterCoverage = hasWater ? (float)waterPixelCount / (chunkSize * chunkSize) : 0f;

        return new WaterChunkData
        {
            ChunkCoord = chunkCoord,
            HasWater = hasWater,
            WaterHeight = waterHeight,
            WaterCoverage = waterCoverage,
            WaterMask = maskData
        };
    }

    public void CreateWaterMesh(int chunkSize, float pixelSize, float waterHeight, 
                                StandardMaterial3D customMaterial, Color waterColor, bool[,] waterMask)
    {
        var chunkWorldSize = chunkSize * pixelSize;
        
        var surfaceTool = new SurfaceTool();
        surfaceTool.Begin(Mesh.PrimitiveType.Triangles);
        
        float halfSize = chunkWorldSize * 0.5f;
        
        Vector3[] vertices = new Vector3[]
        {
            new Vector3(-halfSize, waterHeight, -halfSize),
            new Vector3(halfSize, waterHeight, -halfSize),
            new Vector3(halfSize, waterHeight, halfSize),
            new Vector3(-halfSize, waterHeight, halfSize)
        };
        
        Vector2[] uvs = new Vector2[]
        {
            new Vector2(0, 0),
            new Vector2(1, 0),
            new Vector2(1, 1),
            new Vector2(0, 1)
        };
        
        Vector3 normal = Vector3.Up;
        
        surfaceTool.SetNormal(normal);
        surfaceTool.SetUV(uvs[0]);
        surfaceTool.AddVertex(vertices[0]);
        
        surfaceTool.SetNormal(normal);
        surfaceTool.SetUV(uvs[1]);
        surfaceTool.AddVertex(vertices[1]);
        
        surfaceTool.SetNormal(normal);
        surfaceTool.SetUV(uvs[2]);
        surfaceTool.AddVertex(vertices[2]);
        
        surfaceTool.SetNormal(normal);
        surfaceTool.SetUV(uvs[0]);
        surfaceTool.AddVertex(vertices[0]);
        
        surfaceTool.SetNormal(normal);
        surfaceTool.SetUV(uvs[2]);
        surfaceTool.AddVertex(vertices[2]);
        
        surfaceTool.SetNormal(normal);
        surfaceTool.SetUV(uvs[3]);
        surfaceTool.AddVertex(vertices[3]);
        
        surfaceTool.GenerateNormals();
        surfaceTool.GenerateTangents();
        
        var mesh = surfaceTool.Commit();
        WaterMesh.Mesh = mesh;
        
        if (customMaterial != null)
        {
            _chunkWaterMaterial = customMaterial.Duplicate() as StandardMaterial3D;
        }
        else
        {
            _chunkWaterMaterial = new StandardMaterial3D();
            
            _chunkWaterMaterial.AlbedoColor = waterColor;
            _chunkWaterMaterial.Roughness = 0.1f;
            _chunkWaterMaterial.Metallic = 0.0f;
            
            _chunkWaterMaterial.BlendMode = BaseMaterial3D.BlendModeEnum.Mix;
            _chunkWaterMaterial.DepthDrawMode = BaseMaterial3D.DepthDrawModeEnum.OpaqueOnly;
            _chunkWaterMaterial.CullMode = BaseMaterial3D.CullModeEnum.Back;
        }
        
        var maskTexture = CreateWaterMaskTexture(waterMask, chunkSize);
        _chunkWaterMaterial.AlbedoTexture = maskTexture;
        
        WaterMesh.MaterialOverride = _chunkWaterMaterial;
        
        WaterMesh.CastShadow = GeometryInstance3D.ShadowCastingSetting.Off;
        WaterMesh.GIMode = GeometryInstance3D.GIModeEnum.Disabled;
        WaterMesh.SortingOffset = 0.1f;
    }
    
    private ImageTexture CreateWaterMaskTexture(bool[,] waterMask, int size)
    {
        var image = Image.Create(size, size, false, Image.Format.Rgba8);
        
        for (int y = 0; y < size; y++)
        {
            for (int x = 0; x < size; x++)
            {
                if (waterMask[x, y])
                {
                    image.SetPixel(x, y, new Color(1.0f, 1.0f, 1.0f, 1.0f));
                }
                else
                {
                    image.SetPixel(x, y, new Color(1.0f, 1.0f, 1.0f, 0.0f));
                }
            }
        }
        
        return ImageTexture.CreateFromImage(image);
    }
}

public class WaterChunkData
{
    public Vector2I ChunkCoord { get; set; }
    public bool HasWater { get; set; }
    public float WaterHeight { get; set; }
    public float WaterCoverage { get; set; }
    public bool[,] WaterMask { get; set; }
}