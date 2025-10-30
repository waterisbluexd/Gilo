using Godot;

[GlobalClass]
public partial class ChunkData : GodotObject
{
    public Transform3D[] Transforms { get; set; }
    public Color[] Colors { get; set; }
    public Vector2I ChunkCoord { get; set; }
    
    // Constructor for creating new instances
    public ChunkData()
    {
        Transforms = System.Array.Empty<Transform3D>();
        Colors = System.Array.Empty<Color>();
        ChunkCoord = new Vector2I();
    }
}