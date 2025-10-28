using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

[Tool]
public partial class EnvironmentManager : Node3D
{
    private ResourceSystem _resourceSystem;

    [ExportGroup("Prop Database")]
    [Export] public Godot.Collections.Array<EnvironmentPropData> PropDatabase { get; set; }

    [ExportGroup("Placement Settings")]
    [Export] public bool EnableRandomRotation { get; set; } = true;
    
    [Export(PropertyHint.Range, "0.0,1.0")] 
    public float RandomScaleVariation { get; set; } = 0.2f;
    
    [Export(PropertyHint.Range, "1,32")]
    public int PixelSkipInterval { get; set; } = 4;

    [ExportGroup("Performance")]
    [Export] public bool EnablePropCulling { get; set; } = true;

    private ChunkPixelTerrain _terrain;
    private Dictionary<Vector2I, ChunkPropData> _propChunks = new();
    private Camera3D _camera;

    public override void _Ready()
    {
        SetProcess(true);
        
        _terrain = GetParent<ChunkPixelTerrain>();
        if (_terrain == null)
        {
            GD.PushError("EnvironmentManager must be a child of ChunkPixelTerrain!");
            SetProcess(false);
            return;
        }

        _camera = GetViewport()?.GetCamera3D();
        
        // FIX: Use the static ResourceSystem.Instance property to access the singleton.
        _resourceSystem = ResourceSystem.Instance; 
        
        if (_resourceSystem == null)
        {
            // If the instance is null, create it and add it to the scene root as a fallback.
            _resourceSystem = new ResourceSystem();
            _resourceSystem.Name = "ResourceSystem";
            GetTree().Root.AddChild(_resourceSystem);
        }
        
        CallDeferred(nameof(Initialize));
    }

    private void Initialize()
    {
        if (PropDatabase == null || PropDatabase.Count == 0)
        {
            GD.PushWarning("EnvironmentManager: PropDatabase is empty!");
            return;
        }

        GD.Print($"EnvironmentManager initialized with {PropDatabase.Count} prop types");
    }

    public override void _Process(double delta)
    {
        if (_terrain == null || !_terrain.WorldActive) return;

        UpdatePropChunks();

        if (EnablePropCulling && _camera != null)
            UpdatePropVisibility();
    }

    private void UpdatePropChunks()
    {
        var loadedTerrainChunks = GetLoadedTerrainChunks();
        
        foreach (var chunkCoord in loadedTerrainChunks)
        {
            if (!_propChunks.ContainsKey(chunkCoord))
                GeneratePropChunk(chunkCoord);
        }

        var chunksToUnload = new List<Vector2I>();
        foreach (var coord in _propChunks.Keys)
        {
            if (!loadedTerrainChunks.Contains(coord))
                chunksToUnload.Add(coord);
        }

        foreach (var coord in chunksToUnload)
            UnloadPropChunk(coord);
    }

    private HashSet<Vector2I> GetLoadedTerrainChunks()
    {
        var chunks = new HashSet<Vector2I>();
        
        foreach (Node child in _terrain.GetChildren())
        {
            if (child.Name.ToString().StartsWith("chunk_"))
            {
                var parts = child.Name.ToString().Replace("chunk_(", "").Replace(")", "").Split(",");
                if (parts.Length == 2 && int.TryParse(parts[0].Trim(), out int x) && int.TryParse(parts[1].Trim(), out int z))
                {
                    chunks.Add(new Vector2I(x, z));
                }
            }
        }
        
        return chunks;
    }

    private void GeneratePropChunk(Vector2I chunkCoord)
{
    var chunkPropData = new ChunkPropData { ChunkCoord = chunkCoord };
    
    float chunkWorldSize = _terrain.ChunkSize * _terrain.PixelSize;
    Vector2 chunkWorldOrigin = new Vector2(
        chunkCoord.X * chunkWorldSize,
        chunkCoord.Y * chunkWorldSize
    );

    var biomePixels = new Dictionary<int, List<PixelPosition>>();
    
    for (int z = 0; z < _terrain.ChunkSize; z += PixelSkipInterval)
    {
        for (int x = 0; x < _terrain.ChunkSize; x += PixelSkipInterval)
        {
            float localX = (x * _terrain.PixelSize) + (_terrain.PixelSize * 0.5f);
            float localZ = (z * _terrain.PixelSize) + (_terrain.PixelSize * 0.5f);
            
            float worldX = chunkWorldOrigin.X + localX;
            float worldZ = chunkWorldOrigin.Y + localZ;

            int biomeIndex = _terrain.GetBiomeIndexAt(worldX, worldZ);
            
            if (!biomePixels.ContainsKey(biomeIndex))
                biomePixels[biomeIndex] = new List<PixelPosition>();
            
            biomePixels[biomeIndex].Add(new PixelPosition
            {
                WorldX = worldX,
                WorldZ = worldZ,
                LocalX = localX,
                LocalZ = localZ
            });
        }
    }

    foreach (var propData in PropDatabase)
    {
        if (propData == null) continue;

        var mesh = propData.GetMesh();
        if (mesh == null) continue;

        var propInstances = new List<PropInstance>();
        int instanceIndex = 0; // Track instance index for resource system

        for (int biomeIndex = 0; biomeIndex < 8; biomeIndex++)
        {
            var biomeFlag = (EnvironmentPropData.BiomeFlags)(1 << biomeIndex);
            
            if (!propData.AllowedBiomes.HasFlag(biomeFlag))
                continue;
            
            if (!biomePixels.ContainsKey(biomeIndex))
                continue;

            foreach (var pixel in biomePixels[biomeIndex])
            {
                // MODIFIED: Check if resource should spawn (not harvested)
                if (!_resourceSystem.ShouldSpawnResource(chunkCoord, instanceIndex, propData.Name))
                {
                    instanceIndex++;
                    continue; // Skip harvested resources
                }

                float randomValue = GetDeterministicRandom(pixel.WorldX, pixel.WorldZ, propData.Name);
                if (randomValue < propData.Probability)
                {
                    var instance = CreatePropInstance(
                        pixel.WorldX, pixel.WorldZ, 
                        pixel.LocalX, pixel.LocalZ, 
                        propData
                    );
                    propInstances.Add(instance);

                    // ADDED: Register as harvestable resource
                    // Note: You must ensure 'IsHarvestable' exists on EnvironmentPropData.cs
                    if (propData.IsHarvestable) 
                    {
                        _resourceSystem.RegisterResource(
                            chunkCoord, 
                            instance.WorldPosition, 
                            propData.Name, 
                            instanceIndex
                        );
                    }
                    
                    instanceIndex++;
                }
                else
                {
                    instanceIndex++;
                }
            }
        }

        if (propInstances.Count > 0)
        {
            var mmi = CreateMultiMeshInstance(propInstances, propData, chunkCoord);
            chunkPropData.MultiMeshInstances.Add(mmi);
            AddChild(mmi);
        }
    }

    _propChunks[chunkCoord] = chunkPropData;
}
    private float GetTerrainHeightAt(float worldX, float worldZ)
    {
        // Get height using EXACT same method as terrain
        if (!_terrain.EnableHeightVariation || _terrain.HeightNoise == null)
            return 0f;

        float heightValue = _terrain.HeightNoise.GetNoise2D(worldX, worldZ);
        return heightValue * _terrain.TerrainHeightVariation * _terrain.HeightInfluence;
    }

    private float GetDeterministicRandom(float x, float z, string seed)
    {
        // Hash function for deterministic randomness
        int hash = (x.ToString() + z.ToString() + seed).GetHashCode();
        return (float)((hash & 0xFFFF) / (float)0xFFFF);
    }

    private PropInstance CreatePropInstance(float worldX, float worldZ, float localX, float localZ, EnvironmentPropData propData)
    {
        var transform = Transform3D.Identity;
        
        // Get terrain height at this position
        float terrainHeight = GetTerrainHeightAt(worldX, worldZ);
        
        // Position (relative to chunk center) with correct height
        float chunkWorldSize = _terrain.ChunkSize * _terrain.PixelSize;
        float halfSize = chunkWorldSize * 0.5f;
        transform.Origin = new Vector3(
            localX - halfSize, 
            terrainHeight,
            localZ - halfSize
        );

        // Random rotation
        if (EnableRandomRotation)
        {
            float rotationRandom = GetDeterministicRandom(worldX, worldZ, propData.Name + "_rot");
            float rotationY = rotationRandom * Mathf.Tau;
            transform.Basis = Basis.FromEuler(new Vector3(0, rotationY, 0));
        }

        // Get base scale from prop data (this now respects scene scale!)
        Vector3 scale = propData.GetScale();
        
        // Apply scale variation if enabled
        if (RandomScaleVariation > 0)
        {
            float scaleRandom = GetDeterministicRandom(worldX, worldZ, propData.Name + "_scale");
            float scaleFactor = 1.0f + (scaleRandom - 0.5f) * 2.0f * RandomScaleVariation;
            scale *= scaleFactor;
        }
        
        transform.Basis = transform.Basis.Scaled(scale);

        return new PropInstance
        {
            Transform = transform,
            WorldPosition = new Vector3(worldX, terrainHeight, worldZ)
        };
    }

    private MultiMeshInstance3D CreateMultiMeshInstance(List<PropInstance> instances, EnvironmentPropData propData, Vector2I chunkCoord)
    {
        var mmi = new MultiMeshInstance3D
        {
            Name = $"props_{propData.Name}_{chunkCoord}"
        };

        var mesh = propData.GetMesh();
        if (mesh == null)
        {
            GD.PushError($"Failed to get mesh for prop '{propData.Name}'");
            return mmi;
        }

        var multiMesh = new MultiMesh
        {
            TransformFormat = MultiMesh.TransformFormatEnum.Transform3D,
            Mesh = mesh,
            InstanceCount = instances.Count
        };

        for (int i = 0; i < instances.Count; i++)
        {
            multiMesh.SetInstanceTransform(i, instances[i].Transform);
        }

        mmi.Multimesh = multiMesh;

        // Apply material from prop data if available
        var material = propData.GetMaterial();
        if (material != null)
        {
            mmi.MaterialOverride = material;
        }

        // Position MMI at chunk center in world space
        float chunkWorldSize = _terrain.ChunkSize * _terrain.PixelSize;
        Vector2 chunkWorldOrigin = new Vector2(
            chunkCoord.X * chunkWorldSize,
            chunkCoord.Y * chunkWorldSize
        );
        mmi.Position = new Vector3(
            chunkWorldOrigin.X + chunkWorldSize * 0.5f,
            0,
            chunkWorldOrigin.Y + chunkWorldSize * 0.5f
        );

        mmi.CastShadow = GeometryInstance3D.ShadowCastingSetting.On;
        
        return mmi;
    }

    private void UnloadPropChunk(Vector2I coord)
{
    if (_propChunks.TryGetValue(coord, out var chunkData))
    {
        foreach (var mmi in chunkData.MultiMeshInstances)
        {
            if (IsInstanceValid(mmi))
                mmi.QueueFree();
        }
        _propChunks.Remove(coord);
        
        // Notify ResourceSystem
        _resourceSystem?.UnloadChunk(coord);
    }
}

    private void UpdatePropVisibility()
    {
        var frustum = _camera.GetFrustum();
        float chunkWorldSize = _terrain.ChunkSize * _terrain.PixelSize;

        foreach (var chunkData in _propChunks.Values)
        {
            Vector2 chunkWorldOrigin = new Vector2(
                chunkData.ChunkCoord.X * chunkWorldSize,
                chunkData.ChunkCoord.Y * chunkWorldSize
            );

            var aabb = new Aabb(
                new Vector3(chunkWorldOrigin.X, -_terrain.TerrainHeightVariation, chunkWorldOrigin.Y),
                new Vector3(chunkWorldSize, _terrain.TerrainHeightVariation * 2, chunkWorldSize)
            );

            bool visible = IsInFrustum(aabb, frustum);

            foreach (var mmi in chunkData.MultiMeshInstances)
            {
                if (IsInstanceValid(mmi))
                    mmi.Visible = visible;
            }
        }
    }

    private bool IsInFrustum(in Aabb aabb, Godot.Collections.Array<Plane> planes)
    {
        foreach (var plane in planes)
        {
            var p = aabb.Position;
            var n = plane.Normal;
            if (n.X > 0) p.X += aabb.Size.X;
            if (n.Y > 0) p.Y += aabb.Size.Y;
            if (n.Z > 0) p.Z += aabb.Size.Z;
            if (plane.IsPointOver(p)) return false;
        }
        return true;
    }

    public int GetLoadedPropChunkCount() => _propChunks.Count;

    public void ClearAllProps()
    {
        foreach (var coord in new List<Vector2I>(_propChunks.Keys))
            UnloadPropChunk(coord);
        _propChunks.Clear();
    }
}

public class ChunkPropData
{
    public Vector2I ChunkCoord { get; set; }
    public List<MultiMeshInstance3D> MultiMeshInstances { get; set; } = new();
}

public class PropInstance
{
    public Transform3D Transform { get; set; }
    public Vector3 WorldPosition { get; set; }
}

public class PixelPosition
{
    public float WorldX { get; set; }
    public float WorldZ { get; set; }
    public float LocalX { get; set; }
    public float LocalZ { get; set; }
}