using Godot;

public partial class Owner : Node
{
    [Export] public int OwnerId { get; private set; } = 0;
    [Export] public int FactionValue { get; private set; } = 0;

    [Signal] public delegate void OwnershipChangedEventHandler(int newOwnerId, int newFaction);
    [Signal] public delegate void CapturedEventHandler(int oldOwnerId, int newOwnerId);

    public Faction Faction => (Faction)FactionValue;

    public void Initialize(int ownerId, Faction faction)
    {
        OwnerId = ownerId;
        FactionValue = (int)faction;
        EntityRegistry.Instance?.Register(OwnerId, this, faction);
    }

    public void SetOwner(int newOwnerId, Faction newFaction)
    {
        var old = OwnerId;
        if (old == newOwnerId && Faction == newFaction) return;

        EntityRegistry.Instance?.Unregister(old, this);

        OwnerId = newOwnerId;
        FactionValue = (int)newFaction;

        EntityRegistry.Instance?.Register(OwnerId, this, newFaction);

        EmitSignal(SignalName.OwnershipChanged, newOwnerId, (int)newFaction);
        if (old != newOwnerId)
            EmitSignal(SignalName.Captured, old, newOwnerId);
    }

    public override void _ExitTree()
    {
        EntityRegistry.Instance?.Unregister(OwnerId, this);
        base._ExitTree();
    }

    public bool IsOwnedBy(int id) => OwnerId == id;

    public bool IsAllyOf(int otherOwnerId)
    {
        if (OwnerId == otherOwnerId) return true;
        if (OwnerId == 0 || otherOwnerId == 0) return false;
        var otherFaction = EntityRegistry.Instance?.GetFaction(otherOwnerId) ?? Faction.Owner;
        return otherFaction == Faction && Faction != Faction.Enemy;
    }

    public bool IsEnemyOf(int otherOwnerId)
    {
        if (OwnerId == otherOwnerId) return false;
        if (OwnerId == 0 || otherOwnerId == 0) return false;
        return !IsAllyOf(otherOwnerId);
    }
}
