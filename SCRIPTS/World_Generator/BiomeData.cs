using Godot;

[GlobalClass]
public partial class BiomeData : Resource
{
    [Export] public string BiomeName { get; set; } = "New Biome";
    [Export] public Color BiomeColor { get; set; } = Colors.Green;
    [Export(PropertyHint.Range, "-1.0,1.0")] 
    public float Threshold { get; set; } = 0.0f;
    
    public BiomeData() { }
    
    public BiomeData(string name, Color color, float threshold)
    {
        BiomeName = name;
        BiomeColor = color;
        Threshold = threshold;
    }
}