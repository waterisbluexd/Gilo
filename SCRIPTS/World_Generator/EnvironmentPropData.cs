using Godot;
using System;

[GlobalClass]
public partial class EnvironmentPropData : Resource
{
    public enum PropSourceType
    {
        Mesh,
        PackedScene
    }

    public enum SpawnPattern
    {
        Scattered,      // Random placement (trees, grass)
        Clustered       // Adjacent placement (rocks, hills)
    }

    [Flags]
    public enum BiomeFlags
    {
        Biome1 = 1 << 0,
        Biome2 = 1 << 1,
        Biome3 = 1 << 2,
        Biome4 = 1 << 3,
        Biome5 = 1 << 4,
        Biome6 = 1 << 5,
        Biome7 = 1 << 6,
        Biome8 = 1 << 7
    }

    [ExportGroup("Basic Info")]
    [Export] public string Name { get; set; } = "New Prop";

    [ExportGroup("Prop Source")]
    [Export] public PropSourceType SourceType { get; set; } = PropSourceType.Mesh;
    [Export] public Mesh PropMesh { get; set; }
    [Export] public PackedScene PropScene { get; set; }

    [ExportGroup("Resource Settings")]
    [Export] public bool IsHarvestable { get; set; } = false;
    [Export] public string ResourceType { get; set; } = "Wood";
    [Export(PropertyHint.Range, "1,1000")]
    public int ResourceYield { get; set; } = 50;
    [Export(PropertyHint.Range, "0.5,30.0")]
    public float HarvestTime { get; set; } = 3.0f;

    [ExportGroup("Navigation Collision")]
    [Export] public Vector2 CollisionSize { get; set; } = Vector2.Zero;
    [Export] public bool BlocksNavigation { get; set; } = true;
    [Export] public bool AutoCalculateCollisionSize { get; set; } = true;

    [ExportGroup("Placement Rules")]
    [Export] public SpawnPattern PlacementPattern { get; set; } = SpawnPattern.Scattered;
    [Export(PropertyHint.Flags, "Biome 1,Biome 2,Biome 3,Biome 4,Biome 5,Biome 6,Biome 7,Biome 8")]
    public BiomeFlags AllowedBiomes { get; set; }
    [Export(PropertyHint.Range, "0.0,1.0")]
    public float Probability { get; set; } = 0.05f;
    [Export] public Vector3 FixedScale { get; set; } = Vector3.One;
    [Export] public bool AvoidWater { get; set; } = true;
    [Export] public bool AvoidBeaches { get; set; } = true;

    [ExportGroup("Clustering Settings (for Rocks/Hills)")]
    [Export(PropertyHint.Range, "0.0,1.0")]
    public float ClusterSpreadChance { get; set; } = 0.7f; // Chance to spread to adjacent
    [Export(PropertyHint.Range, "1,8")]
    public int MaxClusterSize { get; set; } = 6; // Max rocks in a cluster
    [Export(PropertyHint.Range, "0.0,1.0")]
    public float ClusterDecayRate { get; set; } = 0.3f; // Probability reduction per step

    [ExportGroup("Advanced Options")]
    [Export] public bool InheritMaterialsFromSource { get; set; } = true;
    [Export] public bool InheritScaleFromScene { get; set; } = true;
    [Export] public StandardMaterial3D OverrideMaterial { get; set; }

    private Mesh _cachedMesh = null;
    private Material _cachedMaterial = null;
    private Vector3 _cachedScale = Vector3.One;
    private Vector2 _cachedCollisionSize = Vector2.Zero;
    private bool _cacheValid = false;

    public Vector2 GetCollisionSize()
    {
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
                if (PropScene == null)
                {
                    _cacheValid = true;
                    return null;
                }

                try
                {
                    var instance = PropScene.Instantiate();
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
                if (PropScene == null) return null;

                try
                {
                    var instance = PropScene.Instantiate();
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
        if (InheritScaleFromScene && SourceType == PropSourceType.PackedScene)
        {
            if (_cacheValid)
                return _cachedScale;

            if (PropScene == null)
                return FixedScale;

            try
            {
                var instance = PropScene.Instantiate();
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
        return GetMesh() != null;
    }

    public void InvalidateCache()
    {
        _cacheValid = false;
        _cachedMesh = null;
        _cachedMaterial = null;
        _cachedCollisionSize = Vector2.Zero;
    }
}