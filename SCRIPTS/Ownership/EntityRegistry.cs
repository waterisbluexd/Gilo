using Godot;
using System.Collections.Generic;

public partial class EntityRegistry : Node
{
    public static EntityRegistry Instance { get; private set; }

    private readonly Dictionary<int, List<Node>> _byOwner = new();
    private readonly Dictionary<int, Faction> _ownerFactions = new();

    public override void _EnterTree()
    {
        if (Instance != null && Instance != this)
        {
            GD.PrintErr($"EntityRegistry already exists. Freeing duplicate at {Name}");
            QueueFree();
            return;
        }
        Instance = this;
    }

    public void Register(int ownerId, Node entity, Faction? faction = null)
    {
        if (ownerId == 0 || entity == null) return;

        if (!_byOwner.TryGetValue(ownerId, out var list))
        {
            list = new List<Node>();
            _byOwner[ownerId] = list;
        }

        if (!list.Contains(entity))
            list.Add(entity);

        if (faction.HasValue)
            _ownerFactions[ownerId] = faction.Value;
    }

    public void Unregister(int ownerId, Node entity)
    {
        if (ownerId == 0 || entity == null) return;

        if (_byOwner.TryGetValue(ownerId, out var list))
        {
            list.Remove(entity);
            if (list.Count == 0)
                _byOwner.Remove(ownerId);
        }
    }

    public IReadOnlyList<Node> GetEntities(int ownerId)
    {
        if (_byOwner.TryGetValue(ownerId, out var list))
            return list.AsReadOnly();
        return new List<Node>().AsReadOnly();
    }

    public IReadOnlyList<T> GetEntitiesByType<T>(int ownerId) where T : Node
    {
        var result = new List<T>();
        var all = GetEntities(ownerId);
        foreach (var entity in all)
        {
            if (entity is T typed)
                result.Add(typed);
        }
        return result.AsReadOnly();
    }

    public Faction GetFaction(int ownerId)
    {
        if (_ownerFactions.TryGetValue(ownerId, out var f))
            return f;
        return Faction.Owner;
    }

    public void SetFaction(int ownerId, Faction faction)
    {
        _ownerFactions[ownerId] = faction;
    }

    public void DebugPrintAllEntities()
    {
        foreach (var kvp in _byOwner)
        {
            var faction = GetFaction(kvp.Key);
            GD.Print($"Owner {kvp.Key} ({faction}): {kvp.Value.Count} entities");
            foreach (var entity in kvp.Value)
                GD.Print($"  - {entity.Name} ({entity.GetType().Name})");
        }
    }

    public int GetEntityCount(int ownerId) => GetEntities(ownerId).Count;

    public int GetTotalEntityCount()
    {
        int total = 0;
        foreach (var list in _byOwner.Values)
            total += list.Count;
        return total;
    }

    public void Clear()
    {
        _byOwner.Clear();
        _ownerFactions.Clear();
    }
}
