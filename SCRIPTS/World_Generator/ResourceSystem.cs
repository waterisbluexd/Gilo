using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

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
        LoadHarvestedData();
        GD.Print("ResourceSystem initialized and ready");
    }

    public override void _ExitTree()
    {
        SaveHarvestedData();
    }

    /// <summary>
    /// Register a resource when a prop chunk is generated
    /// Called from EnvironmentManager during prop generation
    /// </summary>
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

    /// <summary>
    /// Find the nearest resource of a specific type to a given position
    /// GDScript-friendly wrapper
    /// </summary>
    public ResourceInstance FindNearestResource(Vector3 fromPosition, string resourceType, float maxDistance = 100f)
    {
        ResourceInstance nearest = null;
        float nearestDistSq = maxDistance * maxDistance;

        foreach (var chunkData in _chunkResources.Values)
        {
            foreach (var resource in chunkData.Resources)
            {
                if (string.IsNullOrEmpty(resourceType) || 
                    resource.PropName.Contains(resourceType, StringComparison.OrdinalIgnoreCase))
                {
                    float distSq = fromPosition.DistanceSquaredTo(resource.WorldPosition);
                    if (distSq < nearestDistSq)
                    {
                        nearest = resource;
                        nearestDistSq = distSq;
                    }
                }
            }
        }

        return nearest;
    }

    /// <summary>
    /// Get all resources of a specific type within a radius
    /// GDScript-friendly wrapper
    /// </summary>
    public Godot.Collections.Array<ResourceInstance> FindResourcesInRadius(Vector3 center, string resourceType, float radius)
    {
        var results = new Godot.Collections.Array<ResourceInstance>();
        float radiusSq = radius * radius;

        foreach (var chunkData in _chunkResources.Values)
        {
            foreach (var resource in chunkData.Resources)
            {
                if (string.IsNullOrEmpty(resourceType) || 
                    resource.PropName.Contains(resourceType, StringComparison.OrdinalIgnoreCase))
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
    /// GDScript-friendly wrapper
    /// </summary>
    public bool HarvestResource(ResourceInstance resource, EnvironmentManager envManager)
    {
        if (resource == null || _harvestedResources.Contains(resource.ResourceId))
        {
            GD.Print("Resource is null or already harvested");
            return false;
        }

        // Mark as harvested
        _harvestedResources.Add(resource.ResourceId);

        // Remove from tracking
        if (_chunkResources.TryGetValue(resource.ChunkCoord, out var chunkData))
        {
            chunkData.Resources.Remove(resource);
        }

        // Rebuild the MultiMesh without this instance
        RebuildChunkMultiMesh(resource.ChunkCoord, resource.PropName, envManager);

        GD.Print($"✅ Harvested resource: {resource.PropName} at {resource.WorldPosition}");
        return true;
    }

    /// <summary>
    /// Rebuild a specific MultiMesh to exclude harvested resources
    /// </summary>
    private void RebuildChunkMultiMesh(Vector2I chunkCoord, string propName, EnvironmentManager envManager)
    {
        if (envManager == null)
        {
            GD.PushError("EnvironmentManager is null - cannot rebuild MultiMesh");
            return;
        }

        // Find the MultiMeshInstance for this prop type in this chunk
        var mmiName = $"props_{propName}_{chunkCoord}";
        var mmi = envManager.GetNodeOrNull<MultiMeshInstance3D>(mmiName);
        
        if (mmi == null || mmi.Multimesh == null)
        {
            GD.PushWarning($"Could not find MultiMeshInstance: {mmiName}");
            return;
        }

        var multiMesh = mmi.Multimesh;
        int originalCount = multiMesh.InstanceCount;
        
        // Build a HashSet of remaining (non-harvested) instance indices
        var remainingIndices = new HashSet<int>();
        if (_chunkResources.TryGetValue(chunkCoord, out var chunkData))
        {
            foreach (var resource in chunkData.Resources)
            {
                if (resource.PropName == propName)
                    remainingIndices.Add(resource.InstanceIndex);
            }
        }

        // Collect transforms for remaining instances only
        var transforms = new List<Transform3D>();
        for (int i = 0; i < originalCount; i++)
        {
            if (remainingIndices.Contains(i))
            {
                transforms.Add(multiMesh.GetInstanceTransform(i));
            }
        }

        // Rebuild MultiMesh
        if (transforms.Count > 0)
        {
            multiMesh.InstanceCount = transforms.Count;
            for (int i = 0; i < transforms.Count; i++)
            {
                multiMesh.SetInstanceTransform(i, transforms[i]);
            }
            GD.Print($"🔄 Rebuilt MultiMesh {propName}: {originalCount} -> {transforms.Count} instances");
        }
        else
        {
            // All instances harvested - hide the MultiMesh
            multiMesh.InstanceCount = 0;
            mmi.Visible = false;
            GD.Print($"🔄 All {propName} instances harvested in chunk {chunkCoord}");
        }
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

    /// <summary>
    /// Get total count of all registered resources (for debugging)
    /// </summary>
    public int GetTotalResourceCount()
    {
        int count = 0;
        foreach (var chunk in _chunkResources.Values)
            count += chunk.Resources.Count;
        return count;
    }

    /// <summary>
    /// Get count of harvested resources (for debugging)
    /// </summary>
    public int GetHarvestedCount()
    {
        return _harvestedResources.Count;
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
                // Convert HashSet<string> to Godot.Collections.Array
                var harvestedArray = new Godot.Collections.Array();
                foreach (var resourceId in _harvestedResources)
                {
                    harvestedArray.Add(resourceId);
                }
                
                var data = new Godot.Collections.Dictionary
                {
                    ["harvested"] = harvestedArray
                };
                file.StoreVar(data);
                GD.Print($"💾 Saved {_harvestedResources.Count} harvested resources");
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
        {
            GD.Print("No saved harvested data found (this is normal on first run)");
            return;
        }

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
                
                GD.Print($"📂 Loaded {_harvestedResources.Count} harvested resources");
            }
        }
        catch (Exception ex)
        {
            GD.PushError($"Failed to load harvested data: {ex.Message}");
        }
    }

    public void ClearHarvestedData()
    {
        _harvestedResources.Clear();
        if (FileAccess.FileExists(SAVE_PATH))
            DirAccess.RemoveAbsolute(SAVE_PATH);
        
        GD.Print("🗑️ Cleared all harvested resource data");
    }

    /// <summary>
    /// Debug: Print harvested resource IDs (for troubleshooting persistence)
    /// </summary>
    public void PrintHarvestedResources()
    {
        GD.Print($"=== HARVESTED RESOURCES ({_harvestedResources.Count} total) ===");
        
        if (_harvestedResources.Count == 0)
        {
            GD.Print("  (none)");
            return;
        }

        var byChunk = new Dictionary<Vector2I, List<string>>();
        
        foreach (var id in _harvestedResources)
        {
            // Parse chunk coord from ID (format: "X_Y_PropName_Index")
            var parts = id.Split('_');
            if (parts.Length >= 2 && int.TryParse(parts[0], out int x) && int.TryParse(parts[1], out int y))
            {
                var coord = new Vector2I(x, y);
                if (!byChunk.ContainsKey(coord))
                    byChunk[coord] = new List<string>();
                byChunk[coord].Add(id);
            }
        }

        foreach (var kvp in byChunk)
        {
            GD.Print($"  Chunk {kvp.Key}: {kvp.Value.Count} harvested");
            foreach (var id in kvp.Value.Take(3)) // Show first 3
            {
                GD.Print($"    - {id}");
            }
            if (kvp.Value.Count > 3)
                GD.Print($"    ... and {kvp.Value.Count - 3} more");
        }
        
        GD.Print("=====================================");
    }

    #endregion
}

[GlobalClass]
public partial class ResourceInstance : RefCounted
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

public class ChunkResources
{
    public Vector2I ChunkCoord { get; set; }
    public List<ResourceInstance> Resources { get; set; } = new();
}