using Godot;
using System;
using System.Collections.Generic;
using System.Linq;


[GlobalClass]
public partial class ResourceSystem : Node
{
    
    private static ResourceSystem _instance;
    public static ResourceSystem Instance => _instance;

    // Stores all harvestable resource positions
    private Dictionary<Vector2I, ChunkResources> _chunkResources = new();
    
    // Tracks which resources have been harvested (persists across sessions)
    private HashSet<string> _harvestedResources = new();
    
    // Reference to EnvironmentManager for prop data
    private EnvironmentManager _environmentManager;

    public override void _Ready()
    {
        _instance = this;
        // Assuming EnvironmentManager is a parent or easily found relative to this node.
        // If ResourceSystem is a global Autoload, you'll need a different way to set this 
        // after EnvironmentManager is ready, perhaps using CallDeferred or setting it 
        // directly from EnvironmentManager.
        // For now, setting it to null and relying on the HarvestResource method's argument.
        // If you need it globally, you'll need to update this line.
        // If EnvironmentManager is the parent, use:
        // _environmentManager = GetOwner<EnvironmentManager>(); 
        
        LoadHarvestedData();
    }

    public override void _ExitTree()
    {
        SaveHarvestedData();
    }

    public void RegisterResource(Vector2I chunkCoord, Vector3 worldPos, string propName, int instanceIndex)
    {
        string resourceId = GetResourceId(chunkCoord, instanceIndex, propName);
        
        // Skip if already harvested
        if (_harvestedResources.Contains(resourceId))
            return;

        if (!_chunkResources.ContainsKey(chunkCoord))
            _chunkResources[chunkCoord] = new ChunkResources { ChunkCoord = chunkCoord };

        _chunkResources[chunkCoord].Resources.Add(new ResourceInstance
        {
            WorldPosition = worldPos,
            PropName = propName,
            InstanceIndex = instanceIndex,
            ResourceId = resourceId,
            ChunkCoord = chunkCoord
        });
    }

    public ResourceInstance FindNearestResource(Vector3 fromPosition, string resourceType, float maxDistance = 100f)
    {
        ResourceInstance nearest = null;
        float nearestDistSq = maxDistance * maxDistance;

        foreach (var chunkData in _chunkResources.Values)
        {
            foreach (var resource in chunkData.Resources)
            {
                if (!resource.PropName.Contains(resourceType, StringComparison.OrdinalIgnoreCase))
                    continue;

                float distSq = fromPosition.DistanceSquaredTo(resource.WorldPosition);
                if (distSq < nearestDistSq)
                {
                    nearest = resource;
                    nearestDistSq = distSq;
                }
            }
        }

        return nearest;
    }

    /// <summary>
    /// Get all resources of a specific type within a radius
    /// </summary>
    public List<ResourceInstance> FindResourcesInRadius(Vector3 center, string resourceType, float radius)
    {
        var results = new List<ResourceInstance>();
        float radiusSq = radius * radius;

        foreach (var chunkData in _chunkResources.Values)
        {
            foreach (var resource in chunkData.Resources)
            {
                if (resource.PropName.Contains(resourceType, StringComparison.OrdinalIgnoreCase))
                {
                    if (center.DistanceSquaredTo(resource.WorldPosition) <= radiusSq)
                        results.Add(resource);
                }
            }
        }

        return results;
    }

    /// <summary>
    /// Harvest/remove a resource - this marks it as removed permanently
    /// </summary>
    public bool HarvestResource(ResourceInstance resource, EnvironmentManager envManager)
    {
        if (resource == null || _harvestedResources.Contains(resource.ResourceId))
            return false;

        // Mark as harvested
        _harvestedResources.Add(resource.ResourceId);

        // Remove from tracking
        if (_chunkResources.TryGetValue(resource.ChunkCoord, out var chunkData))
        {
            chunkData.Resources.Remove(resource);
        }

        // Rebuild the MultiMesh without this instance
        RebuildChunkMultiMesh(resource.ChunkCoord, resource.PropName, envManager);

        GD.Print($"Harvested resource: {resource.PropName} at {resource.WorldPosition}");
        return true;
    }

    /// <summary>
    /// Rebuild a specific MultiMesh to exclude harvested resources
    /// </summary>
    private void RebuildChunkMultiMesh(Vector2I chunkCoord, string propName, EnvironmentManager envManager)
    {
        // Find the MultiMeshInstance for this prop type in this chunk
        var mmiName = $"props_{propName}_{chunkCoord}";
        // The EnvironmentManager must have the MultiMeshInstance as a direct child 
        // for this GetNode call to work correctly.
        var mmi = envManager.GetNodeOrNull<MultiMeshInstance3D>(mmiName); 
        
        if (mmi == null || mmi.Multimesh == null)
            return;

        var multiMesh = mmi.Multimesh;
        
        // Get all remaining (non-harvested) instances for this prop in this chunk
        var remainingInstances = new List<int>();
        
        if (_chunkResources.TryGetValue(chunkCoord, out var chunkData))
        {
            foreach (var resource in chunkData.Resources)
            {
                if (resource.PropName == propName)
                    remainingInstances.Add(resource.InstanceIndex);
            }
        }

        // Rebuild MultiMesh with only remaining instances
        int originalCount = multiMesh.InstanceCount;
        var transforms = new List<Transform3D>();
        
        for (int i = 0; i < originalCount; i++)
        {
            if (remainingInstances.Contains(i))
                transforms.Add(multiMesh.GetInstanceTransform(i));
        }

        // Update MultiMesh
        multiMesh.InstanceCount = transforms.Count;
        for (int i = 0; i < transforms.Count; i++)
        {
            multiMesh.SetInstanceTransform(i, transforms[i]);
        }

        GD.Print($"Rebuilt MultiMesh {propName} in chunk {chunkCoord}: {originalCount} -> {transforms.Count} instances");
    }

    /// <summary>
    /// Check if a resource should be spawned (returns false if already harvested)
    /// Call this during prop generation
    /// </summary>
    public bool ShouldSpawnResource(Vector2I chunkCoord, int instanceIndex, string propName)
    {
        string resourceId = GetResourceId(chunkCoord, instanceIndex, propName);
        return !_harvestedResources.Contains(resourceId);
    }

    /// <summary>
    /// Unload chunk resources when terrain chunk unloads
    /// </summary>
    public void UnloadChunk(Vector2I chunkCoord)
    {
        _chunkResources.Remove(chunkCoord);
    }

    /// <summary>
    /// Generate unique ID for each resource
    /// </summary>
    private string GetResourceId(Vector2I chunk, int index, string propName)
    {
        return $"{chunk.X}_{chunk.Y}_{propName}_{index}";
    }

    #region Persistence

    private const string SAVE_PATH = "user://harvested_resources.dat";

    private void SaveHarvestedData()
    {
        try
        {
            using var file = FileAccess.Open(SAVE_PATH, FileAccess.ModeFlags.Write);
            if (file != null)
            {
                // FIX: Use Select to convert C# strings to Godot.Variant for serialization
                var harvestedVariants = _harvestedResources.Select(s => (Godot.Variant)s); 
                
                var data = new Godot.Collections.Dictionary
                {
                    ["harvested"] = new Godot.Collections.Array(harvestedVariants) 
                };
                file.StoreVar(data);
                GD.Print($"Saved {_harvestedResources.Count} harvested resources");
            }
        }
        catch (Exception ex)
        {
            GD.PushError($"Failed to save harvested data: {ex.Message}");
        }
    }

    private void LoadHarvestedData()
    {
        if (!FileAccess.FileExists(SAVE_PATH))
            return;

        try
        {
            using var file = FileAccess.Open(SAVE_PATH, FileAccess.ModeFlags.Read);
            if (file != null)
            {
                var data = file.GetVar().AsGodotDictionary();
                var harvestedArray = data["harvested"].AsGodotArray();
                
                _harvestedResources.Clear();
                foreach (var item in harvestedArray)
                {
                    _harvestedResources.Add(item.ToString());
                }
                
                GD.Print($"Loaded {_harvestedResources.Count} harvested resources");
            }
        }
        catch (Exception ex)
        {
            GD.PushError($"Failed to load harvested data: {ex.Message}");
        }
    }

    /// <summary>
    /// Clear all harvested data (useful for world reset)
    /// </summary>
    public void ClearHarvestedData()
    {
        _harvestedResources.Clear();
        if (FileAccess.FileExists(SAVE_PATH))
            DirAccess.RemoveAbsolute(SAVE_PATH);
        
        GD.Print("Cleared all harvested resource data");
    }

    #endregion
}

/// <summary>
/// Represents a single harvestable resource instance
/// </summary>
public class ResourceInstance
{
    public Vector3 WorldPosition { get; set; }
    public string PropName { get; set; }
    public int InstanceIndex { get; set; }
    public string ResourceId { get; set; }
    public Vector2I ChunkCoord { get; set; }
    
    // Optional: Add resource-specific data
    public int ResourceAmount { get; set; } = 100;
    public float HarvestTime { get; set; } = 3.0f;
}

/// <summary>
/// Stores all resources for a single chunk
/// </summary>
public class ChunkResources
{
    public Vector2I ChunkCoord { get; set; }
    public List<ResourceInstance> Resources { get; set; } = new();
}