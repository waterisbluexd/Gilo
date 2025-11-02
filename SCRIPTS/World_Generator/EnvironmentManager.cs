using Godot;
using System;
using System.Collections.Generic;

[Tool]
public partial class EnvironmentManager : Node3D
{
    private ResourceSystem _resourceSystem;
    private Node3D _navigationGrid;

    [ExportGroup("Prop Database")]
    [Export] public Godot.Collections.Array<EnvironmentPropData> PropDatabase { get; set; }

    [ExportGroup("Placement Settings")]
    [Export] public bool EnableRandomRotation { get; set; } = true;
    [Export(PropertyHint.Range, "0.0,1.0")] 
    public float RandomScaleVariation { get; set; } = 0.2f;
    [Export(PropertyHint.Range, "1,32")]
    public int PixelSkipInterval { get; set; } = 1;

    [ExportGroup("Performance")]
    [Export] public bool EnablePropCulling { get; set; } = true;

    [ExportGroup("Navigation Integration")]
    [Export] public Node3D NavigationGridNode { get; set; }
    [Export] public bool RegisterWithNavigationGrid { get; set; } = true;
    [Export] public Vector2 DefaultPropCollisionSize { get; set; } = new Vector2(1.0f, 1.0f);
    
    [ExportGroup("Debug")]
    [Export] public bool EnableDebugLogging { get; set; } = true;

    private ChunkPixelTerrain _terrain;
    private Dictionary<Vector2I, ChunkPropData> _propChunks = new();
    private Camera3D _camera;
    private int _totalResourcesRegistered = 0;
    private bool _resourceSystemReady = false;
    private Dictionary<Vector2I, List<PropNavigationData>> _chunkPropNavData = new();
    
    // OPTIMIZATION: Cache biome pixel data per chunk
    private Dictionary<Vector2I, Dictionary<int, List<PixelPosition>>> _biomePixelCache = new();

    public override void _Ready()
    {
        GlobalPosition = Vector3.Zero;
        SetProcess(true);
        
        _terrain = GetParent<ChunkPixelTerrain>();
        if (_terrain == null)
        {
            GD.PushError("EnvironmentManager must be a child of ChunkPixelTerrain!");
            SetProcess(false);
            return;
        }

        _camera = GetViewport()?.GetCamera3D();
        _resourceSystem = GetNodeOrNull<ResourceSystem>("/root/ResourceSystem");
        
        if (_resourceSystem == null)
        {
            GD.PushError("⚠️ CRITICAL: ResourceSystem not found in AutoLoad!");
            GD.PushError("   Please add ResourceSystem.cs to Project Settings → AutoLoad");
            GD.PushError("   Resource harvesting will NOT work!");
        }
        else
        {
            _resourceSystemReady = true;
            if (EnableDebugLogging)
                GD.Print("✅ ResourceSystem connected successfully");
        }

        if (RegisterWithNavigationGrid)
        {
            _navigationGrid = NavigationGridNode ?? GetNodeOrNull<Node3D>("NavigationGrid");

            if (_navigationGrid == null)
                GD.PushWarning("NavigationGrid not found! Props won't block building placement.");
            else if (EnableDebugLogging)
                GD.Print("✅ NavigationGrid connected successfully");
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

        int harvestableCount = 0;
        foreach (var prop in PropDatabase)
        {
            if (prop != null && prop.IsHarvestable)
                harvestableCount++;
        }

        GD.Print($"EnvironmentManager initialized with {PropDatabase.Count} prop types ({harvestableCount} harvestable)");
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
                    chunks.Add(new Vector2I(x, z));
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
        float halfChunkWorldSize = chunkWorldSize * 0.5f;

        // OPTIMIZATION: Check cache first
        Dictionary<int, List<PixelPosition>> biomePixels;
        if (_biomePixelCache.TryGetValue(chunkCoord, out var cached))
        {
            biomePixels = cached;
        }
        else
        {
            biomePixels = GenerateBiomePixelData(chunkCoord, chunkWorldOrigin, halfChunkWorldSize);
            _biomePixelCache[chunkCoord] = biomePixels;
        }

        int chunkResourceCount = 0;
        int skippedHarvestedCount = 0;
        int propsRegisteredWithNav = 0;

        if (!_chunkPropNavData.ContainsKey(chunkCoord))
            _chunkPropNavData[chunkCoord] = new List<PropNavigationData>();

        foreach (var propData in PropDatabase)
        {
            if (propData == null) continue;

            var mesh = propData.GetMesh();
            if (mesh == null) continue;

            var propInstances = new List<PropInstance>();
            int instanceIndex = 0;

            for (int biomeIndex = 0; biomeIndex < 8; biomeIndex++)
            {
                var biomeFlag = (EnvironmentPropData.BiomeFlags)(1 << biomeIndex);
                
                if (!propData.AllowedBiomes.HasFlag(biomeFlag))
                    continue;
                
                if (!biomePixels.ContainsKey(biomeIndex))
                    continue;

                foreach (var pixel in biomePixels[biomeIndex])
                {
                    bool shouldSpawn = true;
                    
                    if (_resourceSystemReady && propData.IsHarvestable)
                    {
                        shouldSpawn = _resourceSystem.ShouldSpawnResource(chunkCoord, instanceIndex, propData.Name);
                        
                        if (!shouldSpawn)
                        {
                            skippedHarvestedCount++;
                            if (EnableDebugLogging && skippedHarvestedCount <= 3)
                                GD.Print($"🚫 Skipping harvested {propData.Name} at index {instanceIndex} in chunk {chunkCoord}");
                        }
                    }

                    if (!shouldSpawn)
                    {
                        instanceIndex++;
                        continue;
                    }

                    float randomValue = GetDeterministicRandom(pixel.WorldX, pixel.WorldZ, propData.Name);
                    if (randomValue < propData.Probability)
                    {
                        var instance = CreatePropInstance(
                            pixel.WorldX, pixel.WorldZ, 
                            pixel.LocalX, pixel.LocalZ, 
                            propData,
                            chunkWorldOrigin,
                            halfChunkWorldSize
                        );
                        propInstances.Add(instance);

                        if (propData.IsHarvestable && _resourceSystemReady) 
                        {
                            _resourceSystem.RegisterResource(
                                chunkCoord, 
                                instance.WorldPosition, 
                                propData.Name, 
                                instanceIndex
                            );
                            chunkResourceCount++;
                            _totalResourcesRegistered++;
                        }

                        if (RegisterWithNavigationGrid && _navigationGrid != null && propData.BlocksNavigation)
                        {
                            RegisterPropWithNavigation(instance.WorldPosition, propData, chunkCoord);
                            propsRegisteredWithNav++;
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
                var mmi = CreateMultiMeshInstance(propInstances, propData, chunkCoord, chunkWorldOrigin, chunkWorldSize);
                chunkPropData.MultiMeshInstances.Add(mmi);
                AddChild(mmi);
            }
        }

        _propChunks[chunkCoord] = chunkPropData;

        if (EnableDebugLogging && (chunkResourceCount > 0 || skippedHarvestedCount > 0 || propsRegisteredWithNav > 0))
        {
            GD.Print($"🌲 Chunk {chunkCoord}: Spawned {chunkResourceCount} resources, Skipped {skippedHarvestedCount} harvested, Registered {propsRegisteredWithNav} with NavGrid (Total: {_totalResourcesRegistered})");
        }
    }

    // OPTIMIZATION: Separate method for biome pixel generation with caching
    private Dictionary<int, List<PixelPosition>> GenerateBiomePixelData(Vector2I chunkCoord, Vector2 chunkWorldOrigin, float halfChunkWorldSize)
    {
        var biomePixels = new Dictionary<int, List<PixelPosition>>();
        
        for (int z = 0; z < _terrain.ChunkSize; z += PixelSkipInterval)
        {
            for (int x = 0; x < _terrain.ChunkSize; x += PixelSkipInterval)
            {
                float localX = (x * _terrain.PixelSize) - halfChunkWorldSize + (_terrain.PixelSize * 0.5f);
                float localZ = (z * _terrain.PixelSize) - halfChunkWorldSize + (_terrain.PixelSize * 0.5f);

                float worldX = (chunkWorldOrigin.X + halfChunkWorldSize) + localX;
                float worldZ = (chunkWorldOrigin.Y + halfChunkWorldSize) + localZ;

                // OPTIMIZATION: Use combined method to reduce noise calls
                var (biomeIndex, isWater) = _terrain.GetTerrainInfoAt(worldX, worldZ);
                
                if (isWater)
                    continue;
                
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
        
        return biomePixels;
    }

    private void RegisterPropWithNavigation(Vector3 worldPos, EnvironmentPropData propData, Vector2I chunkCoord)
    {
        if (_navigationGrid == null) return;

        Vector2 collisionSize = propData.GetCollisionSize();
        if (collisionSize == Vector2.Zero)
            collisionSize = DefaultPropCollisionSize;

        Vector3 flatWorldPos = new Vector3(
            Mathf.Round(worldPos.X * 100f) / 100f,
            0,
            Mathf.Round(worldPos.Z * 100f) / 100f
        );

        _navigationGrid.Call("register_prop_obstacle", flatWorldPos, collisionSize, propData.Name);
        
        _chunkPropNavData[chunkCoord].Add(new PropNavigationData
        {
            WorldPosition = flatWorldPos,
            CollisionSize = collisionSize,
            PropName = propData.Name
        });
        
        if (EnableDebugLogging && _totalResourcesRegistered <= 5)
            GD.Print($"🌲 Registered prop at {flatWorldPos} (size: {collisionSize})");
    }

    public void UnregisterPropFromNavigation(Vector3 worldPos, EnvironmentPropData propData)
    {
        if (_navigationGrid == null) return;

        Vector2 collisionSize = propData.GetCollisionSize();
        if (collisionSize == Vector2.Zero)
            collisionSize = DefaultPropCollisionSize;

        Vector3 flatWorldPos = new Vector3(
            Mathf.Round(worldPos.X * 100f) / 100f,
            0,
            Mathf.Round(worldPos.Z * 100f) / 100f
        );
        
        _navigationGrid.Call("unregister_prop_obstacle", flatWorldPos, collisionSize);
        
        if (EnableDebugLogging)
            GD.Print($"🪓 Unregistered {propData.Name} from navigation at {flatWorldPos}");
    }

    private float GetTerrainHeightAt(float worldX, float worldZ)
    {
        if (!_terrain.EnableHeightVariation || _terrain.HeightNoise == null)
            return 0f;

        float heightValue = _terrain.HeightNoise.GetNoise2D(worldX, worldZ);
        return heightValue * _terrain.TerrainHeightVariation * _terrain.HeightInfluence;
    }

    private float GetDeterministicRandom(float x, float z, string seed)
    {
        int hash = (x.ToString() + z.ToString() + seed).GetHashCode();
        return (float)((hash & 0xFFFF) / (float)0xFFFF);
    }

    private PropInstance CreatePropInstance(
        float worldX, float worldZ, 
        float localX, float localZ, 
        EnvironmentPropData propData,
        Vector2 chunkWorldOrigin,
        float halfChunkWorldSize)
    {
        var transform = Transform3D.Identity;
        
        float terrainHeight = GetTerrainHeightAt(worldX, worldZ);
        transform.Origin = new Vector3(localX, terrainHeight, localZ);

        if (EnableRandomRotation)
        {
            float rotationRandom = GetDeterministicRandom(worldX, worldZ, propData.Name + "_rot");
            float rotationY = rotationRandom * Mathf.Tau;
            transform.Basis = Basis.FromEuler(new Vector3(0, rotationY, 0));
        }

        Vector3 scale = propData.GetScale();
        
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

    private MultiMeshInstance3D CreateMultiMeshInstance(
        List<PropInstance> instances, 
        EnvironmentPropData propData, 
        Vector2I chunkCoord,
        Vector2 chunkWorldOrigin,
        float chunkWorldSize)
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
            multiMesh.SetInstanceTransform(i, instances[i].Transform);

        mmi.Multimesh = multiMesh;

        var material = propData.GetMaterial();
        if (material != null)
            mmi.MaterialOverride = material;

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
        // OPTIMIZATION: Remove from biome pixel cache
        _biomePixelCache.Remove(coord);
        
        if (_chunkPropNavData.TryGetValue(coord, out var navDataList))
        {
            if (_navigationGrid != null)
            {
                int unregisteredCount = 0;
                foreach (var navData in navDataList)
                {
                    _navigationGrid.Call("unregister_prop_obstacle", navData.WorldPosition, navData.CollisionSize);
                    unregisteredCount++;
                }
                
                if (EnableDebugLogging)
                    GD.Print($"🧹 Unregistered {unregisteredCount} props from navigation (chunk {coord})");
            }
            
            _chunkPropNavData.Remove(coord);
        }

        if (_propChunks.TryGetValue(coord, out var chunkData))
        {
            foreach (var mmi in chunkData.MultiMeshInstances)
            {
                if (IsInstanceValid(mmi))
                    mmi.QueueFree();
            }
            _propChunks.Remove(coord);
            
            if (_resourceSystemReady)
                _resourceSystem.UnloadChunk(coord);
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
    public int GetTotalResourcesRegistered() => _totalResourcesRegistered;

    public void ClearAllProps()
    {
        foreach (var coord in new List<Vector2I>(_propChunks.Keys))
            UnloadPropChunk(coord);
        _propChunks.Clear();
        _chunkPropNavData.Clear();
        _biomePixelCache.Clear(); // Clear cache too
        _totalResourcesRegistered = 0;
    }

    public Node3D GetNavigationGrid() => _navigationGrid;

    public void VerifyNavigationSync()
    {
        if (_navigationGrid == null) return;

        var loadedChunks = GetLoadedTerrainChunks();
        
        var orphanedChunks = new List<Vector2I>();
        foreach (var coord in _chunkPropNavData.Keys)
        {
            if (!loadedChunks.Contains(coord))
                orphanedChunks.Add(coord);
        }

        foreach (var coord in orphanedChunks)
        {
            if (_chunkPropNavData.TryGetValue(coord, out var navDataList))
            {
                foreach (var navData in navDataList)
                    _navigationGrid.Call("unregister_prop_obstacle", navData.WorldPosition, navData.CollisionSize);
                _chunkPropNavData.Remove(coord);
                GD.Print($"🧹 Cleaned orphaned navigation data for chunk {coord}");
            }
        }

        if (EnableDebugLogging)
            GD.Print($"Navigation sync check: {loadedChunks.Count} terrain chunks, {_chunkPropNavData.Count} nav chunks, {orphanedChunks.Count} orphaned");
    }

    public Godot.Collections.Dictionary GetNavigationStats()
    {
        var stats = new Godot.Collections.Dictionary();
        stats["loaded_prop_chunks"] = _propChunks.Count;
        stats["nav_data_chunks"] = _chunkPropNavData.Count;
        
        int totalNavProps = 0;
        foreach (var navList in _chunkPropNavData.Values)
            totalNavProps += navList.Count;
        
        stats["total_nav_props"] = totalNavProps;
        
        if (_navigationGrid != null)
        {
            var propBlockedCount = _navigationGrid.Call("get_prop_blocked_count");
            stats["nav_grid_blocked_cells"] = propBlockedCount;
        }
        
        return stats;
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

public class PropNavigationData
{
    public Vector3 WorldPosition { get; set; }
    public Vector2 CollisionSize { get; set; }
    public string PropName { get; set; }
}