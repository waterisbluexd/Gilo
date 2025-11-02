using Godot;

[GlobalClass]
public partial class ChunkData : GodotObject
{
    public Transform3D[] Transforms { get; set; }
    public Color[] Colors { get; set; }
    public Vector2I ChunkCoord { get; set; }
}