using Godot;

public partial class Castle : Node3D
{
    private Owner _owner;
    private static int _castleCount = 0;
    private int _castleId;

    public override void _Ready()
    {
        _castleId = ++_castleCount;
        Name = $"Castle_{_castleId}";
        
        _owner = GetNode<Owner>("Owner");
        if (_owner != null)
        {
            _owner.OwnershipChanged += OnOwnershipChanged;
            GD.Print($"[{Name}] Ready. OwnerId={_owner.OwnerId}, Faction={_owner.Faction}");
        }
    }

    public void SetCastleOwner(int ownerId, Faction faction)
    {
        if (_owner != null)
        {
            GD.Print($"[{Name}] Setting owner to {ownerId} ({faction})");
            _owner.SetOwner(ownerId, faction);
        }
    }

    public Owner GetCastleOwner() => _owner;

    private void OnOwnershipChanged(int newOwnerId, int newFaction)
    {
        GD.Print($"[{Name}] Owner changed to: {newOwnerId} (Faction: {(Faction)newFaction})");
        
        var allEntities = EntityRegistry.Instance.GetEntities(newOwnerId);
        GD.Print($"[{Name}] Owner {newOwnerId} now has {allEntities.Count} entities total");
    }

    public override void _ExitTree()
    {
        if (_owner != null)
        {
            _owner.OwnershipChanged -= OnOwnershipChanged;
        }
        base._ExitTree();
    }
}
