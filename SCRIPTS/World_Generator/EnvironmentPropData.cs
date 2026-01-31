using Godot;
using System;

[GlobalClass]
public partial class EnvironmentPropData : Resource
{
    public enum PropSourceType
    {
        Mesh,
        PackedScene,
        MultiplePackedScenes
    }

    public enum SpawnPattern
    {
        Scattered,
        Clustered
    }

    public enum CollisionMode
    {
        GridBased,
        Area3D
    }

    [ExportGroup("Basic Info")]
    [Export] public string Name { get; set; } = "New Prop";
    [Export(PropertyHint.Range, "0,100")]
    public int SpawnPriority { get; set; } = 50;

    [ExportGroup("Prop Source")]
    [Export] public PropSourceType SourceType { get; set; } = PropSourceType.Mesh;
    [Export] public Mesh PropMesh { get; set; }
    [Export] public PackedScene PropScene { get; set; }
    [Export] public Godot.Collections.Array<PackedScene> PropSceneVariants { get; set; } = new();

    [ExportGroup("Collision & Navigation")]
    [Export] public CollisionMode CollisionType { get; set; } = CollisionMode.GridBased;
    [Export] public bool BlocksNavigation { get; set; } = true;
    
    // Grid-based collision
    [Export] public Vector2 CollisionSize { get; set; } = Vector2.Zero;
    [Export] public bool AutoCalculateCollisionSize { get; set; } = true;
    
    // Collision Group
    [Export] public string CollisionGroupName { get; set; } = "";
    [Export] public Godot.Collections.Array<string> AvoidGroupNames { get; set; } = new();

    [ExportGroup("Placement Rules")]
    [Export] public SpawnPattern PlacementPattern { get; set; } = SpawnPattern.Scattered;
    [Export] public Godot.Collections.Array<string> AllowedBiomeNames { get; set; } = new();
    [Export(PropertyHint.Range, "0.0,1.0")]
    public float Probability { get; set; } = 0.05f;
    [Export] public Vector3 FixedScale { get; set; } = Vector3.One;
    [Export] public bool AvoidWater { get; set; } = true;
    [Export] public bool AvoidBeaches { get; set; } = true;

    [ExportGroup("Clustering Settings")]
    [Export(PropertyHint.Range, "0.0,1.0")]
    public float ClusterSpreadChance { get; set; } = 0.7f;
    [Export(PropertyHint.Range, "1,8")]
    public int MaxClusterSize { get; set; } = 6;
    [Export(PropertyHint.Range, "0.0,1.0")]
    public float ClusterDecayRate { get; set; } = 0.3f;

    [ExportGroup("Multiple Scenes Settings")]
    [Export(PropertyHint.Range, "0.0,5.0")]
    public float MinDistanceBetweenVariants { get; set; } = 2.0f;
    [Export] public bool RandomizeVariantSelection { get; set; } = true;

    [ExportGroup("Advanced Options")]
    [Export] public bool InheritMaterialsFromSource { get; set; } = true;
    [Export] public bool InheritScaleFromScene { get; set; } = true;
    [Export] public StandardMaterial3D OverrideMaterial { get; set; }

    private Mesh _cachedMesh = null;
    private Material _cachedMaterial = null;
    private Vector3 _cachedScale = Vector3.One;
    private Vector2 _cachedCollisionSize = Vector2.Zero;
    private bool _cacheValid = false;

    public bool UsesArea3DCollision()
    {
        return CollisionType == CollisionMode.Area3D && !string.IsNullOrEmpty(CollisionGroupName);
    }

    public string GetCollisionGroup()
    {
        if (!string.IsNullOrEmpty(CollisionGroupName))
            return CollisionGroupName;
        
        string lowerName = Name.ToLower();
        if (lowerName.Contains("tree")) return "tree_collision";
        if (lowerName.Contains("rock") || lowerName.Contains("boulder")) return "rock_collision";
        if (lowerName.Contains("bush") || lowerName.Contains("shrub")) return "bush_collision";
        
        return "prop_collision";
    }

    public bool HasMultipleScenes()
    {
        return SourceType == PropSourceType.MultiplePackedScenes && 
               PropSceneVariants != null && 
               PropSceneVariants.Count > 0;
    }

    public PackedScene GetRandomSceneVariant(float randomValue)
    {
        if (!HasMultipleScenes())
            return PropScene;

        if (!RandomizeVariantSelection && PropSceneVariants.Count > 0)
            return PropSceneVariants[0];

        int index = Mathf.FloorToInt(randomValue * PropSceneVariants.Count);
        index = Mathf.Clamp(index, 0, PropSceneVariants.Count - 1);
        return PropSceneVariants[index];
    }

    public Vector2 GetCollisionSize()
    {
        if (UsesArea3DCollision())
            return Vector2.Zero;

        if (CollisionSize != Vector2.Zero)
            return CollisionSize;

        if (!AutoCalculateCollisionSize)
            return Vector2.Zero;

        if (_cacheValid && _cachedCollisionSize != Vector2.Zero)
            return _cachedCollisionSize;

        var mesh = GetMesh();
        if (mesh != null)
        {
            var aabb = mesh.GetAabb();
            var scale = GetScale();

            _cachedCollisionSize = new Vector2(
                aabb.Size.X * scale.X,
                aabb.Size.Z * scale.Z
            );

            return _cachedCollisionSize;
        }

        return Vector2.Zero;
    }

    public Mesh GetMesh()
    {
        if (_cacheValid && _cachedMesh != null)
            return _cachedMesh;

        switch (SourceType)
        {
            case PropSourceType.Mesh:
                _cachedMesh = PropMesh;
                _cacheValid = true;
                return PropMesh;

            case PropSourceType.PackedScene:
            case PropSourceType.MultiplePackedScenes:
                var sceneToUse = HasMultipleScenes() ? PropSceneVariants[0] : PropScene;
                if (sceneToUse == null)
                {
                    _cacheValid = true;
                    return null;
                }

                try
                {
                    var instance = sceneToUse.Instantiate();
                    var meshInstance = FindMeshInstanceInNode(instance);

                    if (meshInstance != null)
                    {
                        _cachedMesh = meshInstance.Mesh;

                        if (InheritMaterialsFromSource && OverrideMaterial == null)
                            _cachedMaterial = meshInstance.GetActiveMaterial(0);

                        if (InheritScaleFromScene)
                            _cachedScale = meshInstance.Scale;

                        instance.QueueFree();
                        _cacheValid = true;
                        return _cachedMesh;
                    }

                    instance.QueueFree();
                    GD.PushWarning($"PropData '{Name}': PackedScene doesn't contain a MeshInstance3D!");
                    _cacheValid = true;
                    return null;
                }
                catch (Exception ex)
                {
                    GD.PushError($"PropData '{Name}': Failed to instantiate PackedScene - {ex.Message}");
                    _cacheValid = true;
                    return null;
                }

            default:
                _cacheValid = true;
                return null;
        }
    }

    public Material GetMaterial()
    {
        if (OverrideMaterial != null)
            return OverrideMaterial;

        if (!InheritMaterialsFromSource)
            return null;

        if (_cacheValid && _cachedMaterial != null)
            return _cachedMaterial;

        switch (SourceType)
        {
            case PropSourceType.PackedScene:
            case PropSourceType.MultiplePackedScenes:
                var sceneToUse = HasMultipleScenes() ? PropSceneVariants[0] : PropScene;
                if (sceneToUse == null) return null;

                try
                {
                    var instance = sceneToUse.Instantiate();
                    var meshInstance = FindMeshInstanceInNode(instance);

                    Material material = null;
                    if (meshInstance != null)
                        material = meshInstance.GetActiveMaterial(0);

                    instance.QueueFree();
                    _cachedMaterial = material;
                    return material;
                }
                catch
                {
                    return null;
                }

            default:
                return null;
        }
    }

    public Vector3 GetScale()
    {
        if (InheritScaleFromScene && (SourceType == PropSourceType.PackedScene || SourceType == PropSourceType.MultiplePackedScenes))
        {
            if (_cacheValid)
                return _cachedScale;

            var sceneToUse = HasMultipleScenes() ? PropSceneVariants[0] : PropScene;
            if (sceneToUse == null)
                return FixedScale;

            try
            {
                var instance = sceneToUse.Instantiate();
                var meshInstance = FindMeshInstanceInNode(instance);

                if (meshInstance != null)
                    _cachedScale = meshInstance.Scale;
                else
                    _cachedScale = FixedScale;

                instance.QueueFree();
                return _cachedScale;
            }
            catch (Exception ex)
            {
                GD.PushWarning($"PropData '{Name}': Failed to extract scale from PackedScene - {ex.Message}");
                return FixedScale;
            }
        }

        return FixedScale;
    }

    private MeshInstance3D FindMeshInstanceInNode(Node node)
    {
        if (node is MeshInstance3D meshInstance)
            return meshInstance;

        foreach (Node child in node.GetChildren())
        {
            var found = FindMeshInstanceInNode(child);
            if (found != null)
                return found;
        }

        return null;
    }

    public bool IsValid()
    {
        if (SourceType == PropSourceType.MultiplePackedScenes)
            return PropSceneVariants != null && PropSceneVariants.Count > 0;
        
        return GetMesh() != null || PropScene != null;
    }

    public void InvalidateCache()
    {
        _cacheValid = false;
        _cachedMesh = null;
        _cachedMaterial = null;
        _cachedCollisionSize = Vector2.Zero;
    }
}