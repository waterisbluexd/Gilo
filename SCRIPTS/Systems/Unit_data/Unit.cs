using Godot;

public partial class Unit : Node3D
{
    [Export] public PeasantJob Job;

    private UnitVisuals _visuals;

    public override void _Ready()
    {
        _visuals = GetNodeOrNull<UnitVisuals>("Visuals");

        if (Job == null)
        {
            GD.PrintErr($"{Name} spawned with NO job assigned!");
            return;
        }

        ApplyJob(Job);
    }

    public void AssignJob(PeasantJob newJob)
    {
        if (newJob == null)
        {
            GD.PrintErr("Attempted to assign null job");
            return;
        }

        if (Job == newJob)
            return;

        Job = newJob;
        ApplyJob(Job);
    }

    private void ApplyJob(PeasantJob job)
    {
        if (_visuals != null)
        {
            _visuals.SetModel(job.ModelScene);
        }
    }
}
