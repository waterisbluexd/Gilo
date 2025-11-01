using Godot;
using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Threading;
using System.Threading.Tasks;

[Tool]
public partial class ChunkPixelTerrain : Node3D
{
    [ExportGroup("Chunk Settings")]
    [Export] public int ChunkSize { get; set; } = 32;
    [Export] public int RenderDistance { get; set; } = 4;
    [Export] public int UnloadDistance { get; set; } = 6;

    [ExportGroup("Pixel Terrain Settings")]
    [Export] public float PixelSize { get; set; } = 1.0f;
    [Export] public float TerrainHeightVariation { get; set; } = 16.0f;

    [ExportGroup("Generation Control")]
    [Export] public bool WorldActive { get => _worldActive; set => SetWorldActive(value); }
    [Export] public bool AutoGenerateOnReady { get; set; } = true;

    [ExportGroup("Noise Settings")]
    [Export] public FastNoiseLite PrimaryBiomeNoise { get; set; }
    [Export] public FastNoiseLite SecondaryBiomeNoise { get; set; }
    [Export] public FastNoiseLite HeightNoise { get; set; }
    [Export] public FastNoiseLite WaterNoise { get; set; }
    [Export] public bool AutoCreateDefaultNoise { get; set; } = true;
    [Export(PropertyHint.Range, "0.0,1.0")] public float PrimaryNoiseWeight { get; set; } = 0.75f;
    [Export(PropertyHint.Range, "0.0,1.0")] public float SecondaryNoiseWeight { get; set; } = 0.25f;
    [Export(PropertyHint.Range, "0.0,2.0")] public float NoiseContrast { get; set; } = 1.0f;

    [ExportGroup("Height Settings")]
    [Export] public bool EnableHeightVariation { get; set; } = true;
    [Export(PropertyHint.Range, "0.0,1.0")] public float HeightInfluence { get; set; } = 1.0f;

    [ExportGroup("Water Settings")]
    [Export] public bool EnableWater { get; set; } = true;
    [Export(PropertyHint.Range, "-1.0,1.0")] public float WaterThreshold { get; set; } = -0.3f;
    [Export] public Color WaterColor { get; set; } = new Color(0.2f, 0.4f, 0.8f, 1.0f);
    [Export] public float WaterHeight { get; set; } = -0.5f;

    [ExportGroup("Beach/Sand Settings")]
    [Export] public bool EnableBeaches { get; set; } = true;
    [Export] public FastNoiseLite BeachNoise { get; set; }
    [Export(PropertyHint.Range, "-1.0,1.0")] public float BeachThreshold { get; set; } = 0.3f;
    [Export(PropertyHint.Range, "1.0,10.0")] public float BeachWidth { get; set; } = 3.0f;
    [Export] public Color SandColor { get; set; } = new Color(0.93f, 0.87f, 0.64f, 1.0f);

    [ExportGroup("Biome Colors & Thresholds")]
    [Export] public Color Color1 { get; set; } = new Color(0.169f, 0.239f, 0.075f, 1.0f);
    [Export(PropertyHint.Range, "-1.0,1.0")] public float Threshold1 { get; set; } = -0.6f;
    [Export] public Color Color2 { get; set; } = new Color(0.196f, 0.341f, 0.133f, 1.0f);
    [Export(PropertyHint.Range, "-1.0,1.0")] public float Threshold2 { get; set; } = -0.3f;
    [Export] public Color Color3 { get; set; } = new Color(0.38f, 0.408f, 0.133f, 1.0f);
    [Export(PropertyHint.Range, "-1.0,1.0")] public float Threshold3 { get; set; } = -0.1f;
    [Export] public Color Color4 { get; set; } = new Color(0.447f, 0.569f, 0.267f, 1.0f);
    [Export(PropertyHint.Range, "-1.0,1.0")] public float Threshold4 { get; set; } = 0.1f;
    [Export] public Color Color5 { get; set; } = new Color(0.78f, 0.69f, 0.282f, 1.0f);
    [Export(PropertyHint.Range, "-1.0,1.0")] public float Threshold5 { get; set; } = 0.3f;
    [Export] public Color Color6 { get; set; } = new Color(0.482f, 0.624f, 0.2f, 1.0f);
    [Export(PropertyHint.Range, "-1.0,1.0")] public float Threshold6 { get; set; } = 0.5f;
    [Export] public Color Color7 { get; set; } = new Color(0.545f, 0.702f, 0.22f, 1.0f);
    [Export(PropertyHint.Range, "-1.0,1.0")] public float Threshold7 { get; set; } = 0.7f;
    [Export] public Color Color8 { get; set; } = new Color(0.647f, 0.753f, 0.208f, 1.0f);

    [ExportGroup("Material Settings")]
    [Export] public StandardMaterial3D CustomMaterial { get; set; }

    [ExportGroup("Performance")]
    [Export] public bool UseMultithreading { get; set; } = true;
    [Export(PropertyHint.Range, "1,16")] public int MaxConcurrentThreads { get; set; } = 4;
    [Export] public bool EnableFrustumCulling { get; set; } = true;
    [Export] public int MaxChunksPerFrame { get; set; } = 2;
    [Export] public Node3D Player { get; set; }

    private bool _worldActive;
    private Dictionary<Vector2I, TerrainChunk> _loadedChunks = new();
    private HashSet<Vector2I> _loadingChunks = new();
    private Queue<Vector2I> _generationQueue = new();
    private ConcurrentQueue<ChunkData> _meshCreationQueue = new();
    private SemaphoreSlim _threadSemaphore;
    private CancellationTokenSource _cancellationTokenSource;
    private Color[] _biomeColors;
    private float[] _biomeThresholds;
    private Vector2I _lastPlayerChunk = new Vector2I(99999, 99999);
    private Camera3D _camera;

    public override void _Ready()
    {
        SetProcess(true);
        SetPhysicsProcess(false);
        
        _biomeColors = new[] { Color1, Color2, Color3, Color4, Color5, Color6, Color7, Color8 };
        _biomeThresholds = new[] { Threshold1, Threshold2, Threshold3, Threshold4, Threshold5, Threshold6, Threshold7 };
        
        if (AutoCreateDefaultNoise)
        {
            PrimaryBiomeNoise ??= CreateNoise(0.02f, 2);
            SecondaryBiomeNoise ??= CreateNoise(0.05f, 1);
            if (EnableHeightVariation && HeightNoise == null) HeightNoise = CreateNoise(0.08f, 2);
            if (EnableWater && WaterNoise == null) WaterNoise = CreateNoise(0.03f, 2);
            if (EnableBeaches && BeachNoise == null) BeachNoise = CreateNoise(0.15f, 1);
        }
        
        _camera = GetViewport()?.GetCamera3D();
        Player ??= FindPlayer() ?? _camera;
        
        _threadSemaphore = new SemaphoreSlim(MaxConcurrentThreads, MaxConcurrentThreads);
        _cancellationTokenSource = new CancellationTokenSource();

        if (AutoGenerateOnReady && Player != null)
        {
            _lastPlayerChunk = WorldToChunk(Player.GlobalPosition);
            WorldActive = true;
            UpdateChunks();
        }
    }

    public override void _ExitTree()
    {
        WorldActive = false;
        _cancellationTokenSource?.Cancel();
        _threadSemaphore?.Dispose();
    }

    public override void _Process(double delta)
    {
        if (!_worldActive) return;

        Player ??= _camera ?? GetViewport()?.GetCamera3D();
        
        if (Player != null)
        {
            var playerChunk = WorldToChunk(Player.GlobalPosition);
            if (playerChunk != _lastPlayerChunk)
            {
                _lastPlayerChunk = playerChunk;
                UpdateChunks();
            }
        }

        int processed = 0;
        while (processed++ < MaxChunksPerFrame && _meshCreationQueue.TryDequeue(out var data))
            CreateChunkObject(data);

        if (EnableFrustumCulling && _camera != null) UpdateChunkVisibility();
    }

    private void SetWorldActive(bool value)
    {
        if (_worldActive == value) return;
        _worldActive = value;

        if (_worldActive)
        {
            Player ??= FindPlayer() ?? GetViewport()?.GetCamera3D();
            if (Player != null)
            {
                _lastPlayerChunk = WorldToChunk(Player.GlobalPosition);
                UpdateChunks();
            }
            else _worldActive = false;
        }
        else ClearWorld();
    }

    private FastNoiseLite CreateNoise(float freq, int octaves) => new()
    {
        NoiseType = FastNoiseLite.NoiseTypeEnum.Perlin,
        Frequency = freq,
        FractalType = FastNoiseLite.FractalTypeEnum.Fbm,
        FractalOctaves = octaves,
        Seed = (int)GD.Randi()
    };

    private Node3D FindPlayer()
    {
        var root = GetTree().CurrentScene ?? this;
        var found = root.FindChildren("Player*", "Node3D");
        if (found.Count > 0 && found[0] is Node3D p) return p;
        
        var group = GetTree().GetNodesInGroup("player");
        return group.Count > 0 && group[0] is Node3D g ? g : null;
    }

    private void UpdateChunks()
    {
        if (Player == null) return;

        var playerChunk = WorldToChunk(Player.GlobalPosition);
        var chunksToLoad = new Dictionary<Vector2I, float>();

        for (int x = playerChunk.X - RenderDistance; x <= playerChunk.X + RenderDistance; x++)
            for (int z = playerChunk.Y - RenderDistance; z <= playerChunk.Y + RenderDistance; z++)
            {
                var coord = new Vector2I(x, z);
                if (!_loadedChunks.ContainsKey(coord) && !_loadingChunks.Contains(coord))
                    chunksToLoad[coord] = playerChunk.DistanceSquaredTo(coord);
            }

        var sorted = new List<Vector2I>(chunksToLoad.Keys);
        sorted.Sort((a, b) => chunksToLoad[a].CompareTo(chunksToLoad[b]));
        
        _generationQueue.Clear();
        foreach (var chunk in sorted)
        {
            _generationQueue.Enqueue(chunk);
            if (!_loadedChunks.ContainsKey(chunk) && !_loadingChunks.Contains(chunk))
                LoadChunkAsync(chunk);
        }

        foreach (var coord in new List<Vector2I>(_loadedChunks.Keys))
        {
            int dist = Math.Max(Math.Abs(coord.X - playerChunk.X), Math.Abs(coord.Y - playerChunk.Y));
            if (dist > UnloadDistance) UnloadChunk(coord);
        }
    }

    private void UpdateChunkVisibility()
    {
        var frustum = _camera.GetFrustum();
        float size = ChunkSize * PixelSize;

        foreach (var chunk in _loadedChunks.Values)
        {
            var pos = ChunkToWorld(chunk.ChunkCoord);
            var aabb = new Aabb(new Vector3(pos.X, -TerrainHeightVariation, pos.Y),
                               new Vector3(size, TerrainHeightVariation * 2, size));
            chunk.MultiMeshInstance.Visible = IsInFrustum(aabb, frustum);
        }
    }

    private bool IsInFrustum(in Aabb aabb, Godot.Collections.Array<Plane> planes)
    {
        foreach (var plane in planes)
        {
            var p = aabb.Position;
            var n = plane.Normal;
            if (n.X > 0) p.X += aabb.Size.X;
            if (n.Y > 0) p.Y += aabb.Size.Y;
            if (n.Z > 0) p.Z += aabb.Size.Z;
            if (plane.IsPointOver(p)) return false;
        }
        return true;
    }

    private async void LoadChunkAsync(Vector2I coord)
    {
        if (_cancellationTokenSource == null || _threadSemaphore == null) return;
        _loadingChunks.Add(coord);

        if (UseMultithreading)
        {
            try
            {
                await _threadSemaphore.WaitAsync(_cancellationTokenSource.Token);
                try
                {
                    if (_cancellationTokenSource?.IsCancellationRequested ?? true) return;
                    var data = await Task.Run(() => GenerateChunk(coord), _cancellationTokenSource.Token);
                    if (_worldActive && !_cancellationTokenSource.IsCancellationRequested)
                        CallDeferred(nameof(OnChunkGenerated), data);
                }
                finally { _threadSemaphore?.Release(); }
            }
            catch { _loadingChunks.Remove(coord); }
        }
        else if (!(_cancellationTokenSource?.IsCancellationRequested ?? true))
            OnChunkGenerated(GenerateChunk(coord));
        else
            _loadingChunks.Remove(coord);
    }

    private ChunkData GenerateChunk(Vector2I coord)
    {
        var data = TerrainChunk.Generate(
            coord, ChunkSize, PixelSize, 
            PrimaryBiomeNoise, SecondaryBiomeNoise, HeightNoise, WaterNoise, BeachNoise,
            _biomeColors, _biomeThresholds, 
            EnableHeightVariation, HeightInfluence, TerrainHeightVariation,
            PrimaryNoiseWeight, SecondaryNoiseWeight, NoiseContrast,
            EnableWater, WaterThreshold, WaterColor, WaterHeight,
            EnableBeaches, BeachThreshold, BeachWidth, SandColor);
        return data;
    }

    private void OnChunkGenerated(ChunkData data)
    {
        if (!_worldActive) return;
        if (Engine.IsEditorHint()) CreateChunkObject(data);
        else _meshCreationQueue.Enqueue(data);
    }

    private void CreateChunkObject(ChunkData data)
    {
        _loadingChunks.Remove(data.ChunkCoord);
        if (_loadedChunks.ContainsKey(data.ChunkCoord) || !_worldActive) return;

        var chunk = new TerrainChunk(data.ChunkCoord, data);
        chunk.CreateMesh(ChunkSize, PixelSize, CustomMaterial);
        
        var pos = ChunkToWorld(data.ChunkCoord);
        chunk.MultiMeshInstance.Position = new Vector3(pos.X + ChunkSize * PixelSize * 0.5f, 0, pos.Y + ChunkSize * PixelSize * 0.5f);
        
        AddChild(chunk.MultiMeshInstance);
        _loadedChunks[data.ChunkCoord] = chunk;
    }

    private void UnloadChunk(Vector2I coord)
    {
        if (_loadedChunks.TryGetValue(coord, out var chunk))
        {
            chunk.MultiMeshInstance.QueueFree();
            _loadedChunks.Remove(coord);
        }
    }

    private void ClearWorld()
    {
        foreach (var coord in new List<Vector2I>(_loadedChunks.Keys)) UnloadChunk(coord);
        _loadedChunks.Clear();
        _loadingChunks.Clear();
        _generationQueue.Clear();
        _meshCreationQueue = new ConcurrentQueue<ChunkData>();
    }

    private Vector2I WorldToChunk(Vector3 pos) => new(
        Mathf.FloorToInt(pos.X / (ChunkSize * PixelSize)),
        Mathf.FloorToInt(pos.Z / (ChunkSize * PixelSize))
    );

    private Vector2 ChunkToWorld(Vector2I coord) => new(
        coord.X * ChunkSize * PixelSize,
        coord.Y * ChunkSize * PixelSize
    );

    public int GetLoadedChunkCount() => _loadedChunks.Count;
    public int GetLoadingChunkCount() => _loadingChunks.Count;
    
    public int GetBiomeIndexAt(float worldX, float worldZ)
    {
        float primaryValue = PrimaryBiomeNoise.GetNoise2D(worldX, worldZ);
        float secondaryValue = SecondaryBiomeNoise.GetNoise2D(worldX, worldZ);
        
        float combined = (primaryValue * PrimaryNoiseWeight + 
                         secondaryValue * SecondaryNoiseWeight) * NoiseContrast;
        
        float noiseValue = Mathf.Clamp(combined, -1.0f, 1.0f);

        if (noiseValue < _biomeThresholds[0]) return 0;
        if (noiseValue < _biomeThresholds[1]) return 1;
        if (noiseValue < _biomeThresholds[2]) return 2;
        if (noiseValue < _biomeThresholds[3]) return 3;
        if (noiseValue < _biomeThresholds[4]) return 4;
        if (noiseValue < _biomeThresholds[5]) return 5;
        if (noiseValue < _biomeThresholds[6]) return 6;
        
        return 7;
    }
    
    public bool IsWaterAt(float worldX, float worldZ)
    {
        if (!EnableWater || WaterNoise == null) return false;
        float waterValue = WaterNoise.GetNoise2D(worldX, worldZ);
        return waterValue < WaterThreshold;
    }
}