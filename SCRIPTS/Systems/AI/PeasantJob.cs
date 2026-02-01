using Godot;

[GlobalClass]
public partial class PeasantJob : Resource
{
    [Export] public string JobId = "peasant";
    [Export] public string JobName = "Peasant";
    [Export] public string JobDescription =
        "A humble peasant who waits near the castle and can be assigned to work or training.";

    [Export] public float MovementSpeed = 5.0f;

    [Export] public bool CanWork = false;
    [Export] public bool CanFight = false;
    [Export] public bool CanBeAssigned = true;

    [Export] public string IdleAnimation = "idle";

    [Export] public PackedScene ModelScene;
}
