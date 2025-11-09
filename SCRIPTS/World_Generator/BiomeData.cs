using Godot;

[GlobalClass]
public partial class BiomeData : Resource
{
    [Export] public string BiomeName { get; set; } = "New Biome";
    [Export] public Color BiomeColor { get; set; } = Colors.Green;
    
    [Export(PropertyHint.Range, "-1.0,1.0")] 
    public float ThresholdMin { get; set; } = 0.0f;
    
    [Export(PropertyHint.Range, "-1.0,1.0")] 
    public float ThresholdMax { get; set; } = 1.0f;
    
    [Export] public bool UseRange { get; set; } = false;
    
    [Export(PropertyHint.Range, "-1.0,1.0")] 
    public float Threshold 
    { 
        get => ThresholdMin;
        set => ThresholdMin = value;
    }
    
    public BiomeData() { }
    
    public BiomeData(string name, Color color, float threshold)
    {
        BiomeName = name;
        BiomeColor = color;
        ThresholdMin = threshold;
        ThresholdMax = 1.0f;
        UseRange = false;
    }
    
    public BiomeData(string name, Color color, float minThreshold, float maxThreshold)
    {
        BiomeName = name;
        BiomeColor = color;
        ThresholdMin = minThreshold;
        ThresholdMax = maxThreshold;
        UseRange = true;
    }
    public bool IsInRange(float noiseValue)
    {
        if (UseRange)
        {
            return noiseValue >= ThresholdMin && noiseValue < ThresholdMax;
        }
        else
        {
            // Legacy behavior: just check minimum threshold
            return noiseValue >= ThresholdMin;
        }
    }
}