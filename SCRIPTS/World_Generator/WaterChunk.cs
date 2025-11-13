using Godot;
using System;

public partial class WaterChunk
{
    public Vector2I ChunkCoord { get; private set; }
    public MeshInstance3D WaterMesh { get; private set; }
    private static Shader _defaultWaterShader;
    
    // Store material per chunk so each can have different parameters
    private ShaderMaterial _chunkWaterMaterial;
    
    public WaterChunk(Vector2I coord)
    {
        ChunkCoord = coord;
        WaterMesh = new MeshInstance3D
        {
            Name = $"water_chunk_{coord}"
        };
    }

    public static void InitializeDefaultShader()
    {
        if (_defaultWaterShader != null) return;
        
        _defaultWaterShader = new Shader();
        _defaultWaterShader.Code = @"
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 water_color : source_color = vec4(0.2, 0.4, 0.8, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.1;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D water_mask : hint_default_white;
uniform float mask_threshold : hint_range(0.0, 1.0) = 0.5;

void fragment() {
    // Sample the water mask texture
    float mask = texture(water_mask, UV).r;
    
    // Discard pixels that aren't water
    if (mask < mask_threshold) {
        discard;
    }
    
    ALBEDO = water_color.rgb;
    ALPHA = water_color.a;
    ROUGHNESS = roughness;
    METALLIC = metallic;
}
";
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
        
        // Create water mask data
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
                                Shader customShader, Color waterColor, bool[,] waterMask)
    {
        var chunkWorldSize = chunkSize * pixelSize;
        
        // Create a single large quad for the entire chunk
        var surfaceTool = new SurfaceTool();
        surfaceTool.Begin(Mesh.PrimitiveType.Triangles);
        
        float halfSize = chunkWorldSize * 0.5f;
        
        // Define the quad vertices (centered at origin)
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
        
        // First triangle
        surfaceTool.SetNormal(normal);
        surfaceTool.SetUV(uvs[0]);
        surfaceTool.AddVertex(vertices[0]);
        
        surfaceTool.SetNormal(normal);
        surfaceTool.SetUV(uvs[1]);
        surfaceTool.AddVertex(vertices[1]);
        
        surfaceTool.SetNormal(normal);
        surfaceTool.SetUV(uvs[2]);
        surfaceTool.AddVertex(vertices[2]);
        
        // Second triangle
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
        
        // Create shader material (instance per chunk so parameters are editable)
        _chunkWaterMaterial = new ShaderMaterial();
        
        if (customShader != null)
        {
            _chunkWaterMaterial.Shader = customShader;
        }
        else
        {
            InitializeDefaultShader();
            _chunkWaterMaterial.Shader = _defaultWaterShader;
        }
        
        // Set default shader parameters
        _chunkWaterMaterial.SetShaderParameter("water_color", waterColor);
        _chunkWaterMaterial.SetShaderParameter("roughness", 0.1f);
        _chunkWaterMaterial.SetShaderParameter("metallic", 0.0f);
        
        // Create water mask texture
        var maskTexture = CreateWaterMaskTexture(waterMask, chunkSize);
        _chunkWaterMaterial.SetShaderParameter("water_mask", maskTexture);
        _chunkWaterMaterial.SetShaderParameter("mask_threshold", 0.5f);
        
        WaterMesh.MaterialOverride = _chunkWaterMaterial;
        
        // Proper rendering settings
        WaterMesh.CastShadow = GeometryInstance3D.ShadowCastingSetting.Off;
        WaterMesh.GIMode = GeometryInstance3D.GIModeEnum.Disabled;
        WaterMesh.SortingOffset = 0.1f;
        WaterMesh.Transparency = 0.0f;
    }
    
    private ImageTexture CreateWaterMaskTexture(bool[,] waterMask, int size)
    {
        var image = Image.Create(size, size, false, Image.Format.R8);
        
        for (int y = 0; y < size; y++)
        {
            for (int x = 0; x < size; x++)
            {
                // White where there's water, black where there isn't
                byte value = waterMask[x, y] ? (byte)255 : (byte)0;
                image.SetPixel(x, y, new Color(value / 255f, value / 255f, value / 255f, 1.0f));
            }
        }
        
        var texture = ImageTexture.CreateFromImage(image);
        texture.SetMeta("import", false); // Don't try to import
        return texture;
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