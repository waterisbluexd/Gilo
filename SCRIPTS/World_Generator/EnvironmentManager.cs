using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

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

    [ExportGroup("Area3D Collision Settings")]
    [Export] public float Area3DCheckRadius { get; set; } = 5.0f;  // NEW: Radius for Area3D overlap checks
    [Export] public bool EnableArea3DVisualization { get; set; } = false;  // NEW: Debug visualization

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
    private Dictionary<Vector2I, Dictionary<int, List<PixelPosition>>> _biomePixelCache = new();
    private int _biomeCount = 8;
    private Dictionary<EnvironmentPropData, HashSet<int>> _propBiomeIndexCache = new();

    // NEW: Track ALL prop instances for collision checking (both Area3D and grid-based)
    private Dictionary<Vector2I, List<PropPlacementData>> _chunkPlacedProps = new();
    private List<EnvironmentPropData> _sortedPropDatabase = new();  // Sorted by priority

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

        _biomeCount = _terrain.GetBiomeCount();
        GD.Print($"🌍 EnvironmentManager detected {_biomeCount} biomes");

        _camera = GetViewport()?.GetCamera3D();
        _resourceSystem = GetNodeOrNull<ResourceSystem>("/root/ResourceSystem");
        
        if (_resourceSystem == null)
        {
            GD.PushError("⚠️ CRITICAL: ResourceSystem not found in AutoLoad!");
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
        if (_terrain == null)
        {
            GD.PushError("EnvironmentManager: Terrain not found in Initialize!");
            return;
        }
        
        if (PropDatabase == null || PropDatabase.Count == 0)
        {
            GD.PushWarning("EnvironmentManager: PropDatabase is empty!");
            return;
        }

        // NEW: Sort props by priority (higher priority spawns first)
        _sortedPropDatabase = new List<EnvironmentPropData>(PropDatabase);
        _sortedPropDatabase.Sort((a, b) => b.SpawnPriority.CompareTo(a.SpawnPriority));

        // Build biome name-to-index lookup cache
        _propBiomeIndexCache.Clear();
        var biomeNameLookup = new Dictionary<string, int>();
        for (int i = 0; i < _terrain.GetBiomeCount(); i++)
        {
            string biomeName = _terrain.GetBiomeName(i);
            if (!string.IsNullOrEmpty(biomeName) && !biomeNameLookup.ContainsKey(biomeName))
            {
                biomeNameLookup[biomeName] = i;
            }
        }

        int harvestableCount = 0;
        int clusteredCount = 0;
        int area3DCount = 0;

        foreach (var prop in PropDatabase)
        {
            if (prop != null)
            {
                if (prop.IsHarvestable) harvestableCount++;
                if (prop.PlacementPattern == EnvironmentPropData.SpawnPattern.Clustered) clusteredCount++;
                if (prop.UsesArea3DCollision()) area3DCount++;
                
                var allowedIndices = new HashSet<int>();
                if (prop.AllowedBiomeNames != null)
                {
                    foreach (var allowedName in prop.AllowedBiomeNames)
                    {
                        if (biomeNameLookup.TryGetValue(allowedName, out int index))
                        {
                            allowedIndices.Add(index);
                        }
                        else if (EnableDebugLogging)
                        {
                            GD.PushWarning($"Prop '{prop.Name}' wants to spawn in biome '{allowedName}', but this biome is not defined.");
                        }
                    }
                }
                _propBiomeIndexCache[prop] = allowedIndices;
            }
        }

        GD.Print($"EnvironmentManager initialized: {PropDatabase.Count} props ({harvestableCount} harvestable, {clusteredCount} clustered, {area3DCount} Area3D)");
        GD.Print($"Spawn priority order: {string.Join(", ", _sortedPropDatabase.Select(p => $"{p.Name}({p.SpawnPriority})"))}");
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

        if (!_chunkPlacedProps.ContainsKey(chunkCoord))
            _chunkPlacedProps[chunkCoord] = new List<PropPlacementData>();

        // NEW: Process props in priority order (HIGHEST FIRST)
        foreach (var propData in _sortedPropDatabase)
        {
            if (propData == null) continue;

            var mesh = propData.GetMesh();
            if (mesh == null && !propData.HasMultipleScenes()) continue;

            if (propData.PlacementPattern == EnvironmentPropData.SpawnPattern.Scattered)
            {
                GenerateScatteredProps(propData, biomePixels, chunkCoord, chunkWorldOrigin, 
                    halfChunkWorldSize, chunkPropData, ref chunkResourceCount, 
                    ref skippedHarvestedCount, ref propsRegisteredWithNav);
            }
            else if (propData.PlacementPattern == EnvironmentPropData.SpawnPattern.Clustered)
            {
                GenerateClusteredProps(propData, biomePixels, chunkCoord, chunkWorldOrigin, 
                    halfChunkWorldSize, chunkPropData, ref chunkResourceCount, 
                    ref skippedHarvestedCount, ref propsRegisteredWithNav);
            }
        }

        _propChunks[chunkCoord] = chunkPropData;

        if (EnableDebugLogging && (chunkResourceCount > 0 || skippedHarvestedCount > 0 || propsRegisteredWithNav > 0))
        {
            GD.Print($"🌲 Chunk {chunkCoord}: Spawned {chunkResourceCount} resources, Skipped {skippedHarvestedCount} harvested, Registered {propsRegisteredWithNav} with NavGrid");
        }
    }

    // NEW: Check if a position overlaps with ANY existing props (Area3D or grid-based)
    private bool CheckPropCollision(Vector3 worldPos, EnvironmentPropData propData, Vector2I chunkCoord)
    {
        if (!_chunkPlacedProps.TryGetValue(chunkCoord, out var existingProps))
            return false;  // No props to collide with

        // Get the groups this prop should avoid
        var avoidGroups = propData.AvoidGroupNames ?? new Godot.Collections.Array<string>();
        
        if (avoidGroups.Count == 0)
            return false;  // Not avoiding anything

        // Check against all existing props in this chunk
        foreach (var existingProp in existingProps)
        {
            // Check if this prop should avoid the existing prop's group
            if (avoidGroups.Contains(existingProp.GroupName))
            {
                float distance = worldPos.DistanceTo(existingProp.WorldPosition);
                
                // Calculate minimum distance needed
                float minDist = Area3DCheckRadius;
                
                // Use custom distance if specified
                if (propData.HasMultipleScenes() && propData.MinDistanceBetweenVariants > 0)
                    minDist = propData.MinDistanceBetweenVariants;
                
                // Also consider the existing prop's collision size
                if (existingProp.CollisionRadius > 0)
                    minDist = Mathf.Max(minDist, existingProp.CollisionRadius);

                if (distance < minDist)
                {
                    if (EnableDebugLogging)
                        GD.Print($"  ❌ {propData.Name} blocked by {existingProp.PropName} (group: {existingProp.GroupName}, dist: {distance:F2}m < {minDist:F2}m required)");
                    return true;  // Collision detected
                }
            }
        }

        return false;  // No collision
    }

    // NEW: Register a placed prop for future collision checks
    private void RegisterPlacedProp(Vector3 worldPos, EnvironmentPropData propData, Vector2I chunkCoord)
    {
        if (!_chunkPlacedProps.ContainsKey(chunkCoord))
            _chunkPlacedProps[chunkCoord] = new List<PropPlacementData>();

        // Get the group name from prop data
        string groupName = propData.CollisionGroupName;

        // Calculate collision radius from collision size
        float collisionRadius = 0;
        if (propData.UsesArea3DCollision())
        {
            collisionRadius = Area3DCheckRadius;
        }
        else
        {
            var collisionSize = propData.GetCollisionSize();
            collisionRadius = Mathf.Max(collisionSize.X, collisionSize.Y) * 0.5f;
            if (collisionRadius == 0) collisionRadius = 1.0f; // Default for grid props
        }

        _chunkPlacedProps[chunkCoord].Add(new PropPlacementData
        {
            WorldPosition = worldPos,
            PropName = propData.Name,
            GroupName = groupName,
            CollisionRadius = collisionRadius,
            UsesArea3D = propData.UsesArea3DCollision()
        });

        if (EnableDebugLogging && _chunkPlacedProps[chunkCoord].Count <= 5)
        {
            GD.Print($"  📍 Registered {propData.Name} at {worldPos} (group: {groupName}, radius: {collisionRadius:F2})");
        }
    }

    private void GenerateScatteredProps(
        EnvironmentPropData propData, 
        Dictionary<int, List<PixelPosition>> biomePixels,
        Vector2I chunkCoord, Vector2 chunkWorldOrigin, float halfChunkWorldSize,
        ChunkPropData chunkPropData, ref int chunkResourceCount, 
        ref int skippedHarvestedCount, ref int propsRegisteredWithNav)
    {
        var propInstances = new List<PropInstance>();
        int instanceIndex = 0;

        if (!_propBiomeIndexCache.TryGetValue(propData, out var allowedBiomeIndices))
        {
            if (EnableDebugLogging)
                GD.PushError($"Failed to find biome cache for prop '{propData.Name}'");
            return;
        }

        if (allowedBiomeIndices.Count == 0)
            return;

        foreach (int biomeIndex in allowedBiomeIndices)
        {
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
                            GD.Print($"🚫 Skipping harvested {propData.Name} at index {instanceIndex}");
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
                    Vector3 worldPos = new Vector3(pixel.WorldX, 0, pixel.WorldZ);

                    // NEW: Check collision with ALL existing props (not just Area3D)
                    if (CheckPropCollision(worldPos, propData, chunkCoord))
                    {
                        instanceIndex++;
                        continue;  // Skip this placement
                    }

                    var instance = CreatePropInstance(
                        pixel.WorldX, pixel.WorldZ, 
                        pixel.LocalX, pixel.LocalZ, 
                        propData,
                        chunkWorldOrigin,
                        halfChunkWorldSize,
                        randomValue
                    );
                    propInstances.Add(instance);

                    // NEW: Register this prop for future collision checks
                    RegisterPlacedProp(instance.WorldPosition, propData, chunkCoord);

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
                }
                
                instanceIndex++;
            }
        }

        if (propInstances.Count > 0)
        {
            // Handle multiple scene variants
            if (propData.HasMultipleScenes())
            {
                CreateMultipleSceneInstances(propInstances, propData, chunkCoord, chunkPropData);
            }
            else
            {
                var mmi = CreateMultiMeshInstance(propInstances, propData, chunkCoord, chunkWorldOrigin, 
                    _terrain.ChunkSize * _terrain.PixelSize);
                chunkPropData.MultiMeshInstances.Add(mmi);
                AddChild(mmi);
            }
        }
    }

    // NEW: Create individual scene instances for multiple scene variants
    private void CreateMultipleSceneInstances(
        List<PropInstance> instances, 
        EnvironmentPropData propData, 
        Vector2I chunkCoord,
        ChunkPropData chunkPropData)
    {
        foreach (var instance in instances)
        {
            float variantRandom = GetDeterministicRandom(instance.WorldPosition.X, instance.WorldPosition.Z, propData.Name + "_variant");
            var scene = propData.GetRandomSceneVariant(variantRandom);
            
            if (scene == null) continue; 

            try
            {
                var sceneInstance = scene.Instantiate<Node3D>();
                sceneInstance.GlobalPosition = instance.WorldPosition;
                sceneInstance.Rotation = new Vector3(0, instance.Transform.Basis.GetEuler().Y, 0);
                sceneInstance.Scale = instance.Transform.Basis.Scale;
                sceneInstance.Name = $"{propData.Name}_{chunkCoord}_{instances.IndexOf(instance)}";

                // Add to collision group
                string groupName = propData.CollisionGroupName;
                sceneInstance.AddToGroup(groupName);

                AddChild(sceneInstance);
                chunkPropData.SceneInstances.Add(sceneInstance);
            }
            catch (Exception ex)
            {
                GD.PushError($"Failed to instantiate scene for {propData.Name}: {ex.Message}");
            }
        }
    }

    private void GenerateClusteredProps(
        EnvironmentPropData propData, 
        Dictionary<int, List<PixelPosition>> biomePixels,
        Vector2I chunkCoord, Vector2 chunkWorldOrigin, float halfChunkWorldSize,
        ChunkPropData chunkPropData, ref int chunkResourceCount, 
        ref int skippedHarvestedCount, ref int propsRegisteredWithNav)
    {
        var propInstances = new List<PropInstance>();
        int instanceIndex = 0;

        var processedPixels = new HashSet<Vector2I>();

        if (!_propBiomeIndexCache.TryGetValue(propData, out var allowedBiomeIndices))
        {
            if (EnableDebugLogging)
                GD.PushError($"Failed to find biome cache for prop '{propData.Name}'");
            return;
        }

        if (allowedBiomeIndices.Count == 0)
            return;

        foreach (int biomeIndex in allowedBiomeIndices)
        {
            if (!biomePixels.ContainsKey(biomeIndex))
                continue;

            var pixelGrid = new Dictionary<Vector2I, PixelPosition>();
            foreach (var pixel in biomePixels[biomeIndex])
            {
                var gridCoord = new Vector2I(
                    Mathf.FloorToInt(pixel.LocalX / _terrain.PixelSize),
                    Mathf.FloorToInt(pixel.LocalZ / _terrain.PixelSize)
                );
                if (!pixelGrid.ContainsKey(gridCoord))
                    pixelGrid[gridCoord] = pixel;
            }

            foreach (var kvp in pixelGrid)
            {
                var gridCoord = kvp.Key;
                
                if (processedPixels.Contains(gridCoord))
                    continue;

                Vector3 seedWorldPos = new Vector3(kvp.Value.WorldX, 0, kvp.Value.WorldZ);
                
                // NEW: Check collision for cluster seed
                if (CheckPropCollision(seedWorldPos, propData, chunkCoord))
                    continue;

                float randomValue = GetDeterministicRandom(kvp.Value.WorldX, kvp.Value.WorldZ, propData.Name);
                
                if (randomValue < propData.Probability)
                {
                    var cluster = GenerateCluster(kvp.Value, gridCoord, pixelGrid, processedPixels, 
                        propData, chunkCoord, chunkWorldOrigin, halfChunkWorldSize, ref instanceIndex);
                    
                    propInstances.AddRange(cluster);

                    foreach (var instance in cluster)
                    {
                        // NEW: Register clustered props
                        RegisterPlacedProp(instance.WorldPosition, propData, chunkCoord);

                        if (propData.IsHarvestable && _resourceSystemReady) 
                        {
                            _resourceSystem.RegisterResource(
                                chunkCoord, 
                                instance.WorldPosition, 
                                propData.Name, 
                                instanceIndex++
                            );
                            chunkResourceCount++;
                            _totalResourcesRegistered++;
                        }

                        if (RegisterWithNavigationGrid && _navigationGrid != null && propData.BlocksNavigation)
                        {
                            RegisterPropWithNavigation(instance.WorldPosition, propData, chunkCoord);
                            propsRegisteredWithNav++;
                        }
                    }
                }
            }
        }

        if (propInstances.Count > 0)
        {
            if (propData.HasMultipleScenes())
            {
                CreateMultipleSceneInstances(propInstances, propData, chunkCoord, chunkPropData);
            }
            else
            {
                var mmi = CreateMultiMeshInstance(propInstances, propData, chunkCoord, chunkWorldOrigin, 
                    _terrain.ChunkSize * _terrain.PixelSize);
                chunkPropData.MultiMeshInstances.Add(mmi);
                AddChild(mmi);
            }
        }
    }

    private List<PropInstance> GenerateCluster(
        PixelPosition seedPixel, Vector2I seedGrid,
        Dictionary<Vector2I, PixelPosition> pixelGrid,
        HashSet<Vector2I> processedPixels,
        EnvironmentPropData propData, Vector2I chunkCoord,
        Vector2 chunkWorldOrigin, float halfChunkWorldSize, ref int instanceIndex)
    {
        var cluster = new List<PropInstance>();
        var queue = new Queue<(Vector2I coord, float probability)>();
        
        queue.Enqueue((seedGrid, propData.Probability));
        
        int clusterSize = 0;

        while (queue.Count > 0 && clusterSize < propData.MaxClusterSize)
        {
            var (currentGrid, currentProb) = queue.Dequeue();
            
            if (processedPixels.Contains(currentGrid))
                continue;
            
            if (!pixelGrid.TryGetValue(currentGrid, out var pixel))
                continue;

            Vector3 worldPos = new Vector3(pixel.WorldX, 0, pixel.WorldZ);

            // NEW: Check collision for cluster members
            if (CheckPropCollision(worldPos, propData, chunkCoord))
                continue;

            processedPixels.Add(currentGrid);

            float variantRandom = GetDeterministicRandom(pixel.WorldX, pixel.WorldZ, propData.Name + "_cluster");
            var instance = CreatePropInstance(
                pixel.WorldX, pixel.WorldZ, 
                pixel.LocalX, pixel.LocalZ, 
                propData,
                chunkWorldOrigin,
                halfChunkWorldSize,
                variantRandom
            );
            cluster.Add(instance);
            clusterSize++;

            var adjacentCells = new Vector2I[]
            {
                new Vector2I(currentGrid.X + 1, currentGrid.Y),
                new Vector2I(currentGrid.X - 1, currentGrid.Y),
                new Vector2I(currentGrid.X, currentGrid.Y + 1),
                new Vector2I(currentGrid.X, currentGrid.Y - 1),
                new Vector2I(currentGrid.X + 1, currentGrid.Y + 1),
                new Vector2I(currentGrid.X - 1, currentGrid.Y - 1),
                new Vector2I(currentGrid.X + 1, currentGrid.Y - 1),
                new Vector2I(currentGrid.X - 1, currentGrid.Y + 1)
            };

            foreach (var adjacentGrid in adjacentCells)
            {
                if (processedPixels.Contains(adjacentGrid))
                    continue;
                
                if (!pixelGrid.ContainsKey(adjacentGrid))
                    continue;

                float newProb = currentProb * (1.0f - propData.ClusterDecayRate);
                
                float spreadRandom = GetDeterministicRandom(
                    adjacentGrid.X * 100f, adjacentGrid.Y * 100f, 
                    propData.Name + currentGrid.X + currentGrid.Y);
                
                if (spreadRandom < propData.ClusterSpreadChance && newProb > 0.01f)
                {
                    queue.Enqueue((adjacentGrid, newProb));
                }
            }
        }

        return cluster;
    }

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

        // Use Area3D for navigation if available, otherwise use grid-based
        Vector2 collisionSize = propData.UsesArea3DCollision() ? 
            DefaultPropCollisionSize : propData.GetCollisionSize();
        
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
    }

    public void UnregisterPropFromNavigation(Vector3 worldPos, EnvironmentPropData propData)
    {
        if (_navigationGrid == null) return;

        Vector2 collisionSize = propData.UsesArea3DCollision() ? 
            DefaultPropCollisionSize : propData.GetCollisionSize();
        
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
        float halfChunkWorldSize,
        float randomSeed)
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
        _biomePixelCache.Remove(coord);
        
        // Clear prop placement tracking
        _chunkPlacedProps.Remove(coord);

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

            // NEW: Free scene instances
            foreach (var sceneInstance in chunkData.SceneInstances)
            {
                if (IsInstanceValid(sceneInstance))
                    sceneInstance.QueueFree();
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

            foreach (var sceneInstance in chunkData.SceneInstances)
            {
                if (IsInstanceValid(sceneInstance))
                    sceneInstance.Visible = visible;
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
        _chunkPlacedProps.Clear();
        _biomePixelCache.Clear();
        _totalResourcesRegistered = 0;
    }

    public Node3D GetNavigationGrid() => _navigationGrid;
}

public class ChunkPropData
{
    public Vector2I ChunkCoord { get; set; }
    public List<MultiMeshInstance3D> MultiMeshInstances { get; set; } = new();
    public List<Node3D> SceneInstances { get; set; } = new();  // NEW: For multiple scene support
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

// NEW: Universal prop tracking for collision detection
public class PropPlacementData
{
    public Vector3 WorldPosition { get; set; }
    public string PropName { get; set; }
    public string GroupName { get; set; }  // The group this prop belongs to (e.g., "tree_collision", "rock_collision")
    public float CollisionRadius { get; set; }  // Radius for distance checks
    public bool UsesArea3D { get; set; }
}