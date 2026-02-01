using Godot;

public partial class UnitVisuals : Node3D
{
    private Node3D _currentModel;

    public void SetModel(PackedScene modelScene)
    {
        if (_currentModel != null)
        {
            _currentModel.QueueFree();
            _currentModel = null;
        }

        if (modelScene == null)
            return;

        _currentModel = modelScene.Instantiate<Node3D>();
        AddChild(_currentModel);
    }
}
