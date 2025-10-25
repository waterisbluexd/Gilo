using Godot;
using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Threading;
using System.Threading.Tasks;

[Tool]
public partial class ChunkPixelTerrain : Node3D
{
	#region Exports
	[ExportGroup("Chunk Settings")]
	[Export] public int ChunkSize { get; set; } = 32;
	[Export] public int RenderDistance { get; set; } = 4;
	[Export] public int UnloadDistance { get; set; } = 6;
	[Export] public string SavePath { get; set; } = "res://world_cache/";

	[ExportGroup("Pixel Terrain Settings")]
	[Export] public float PixelSize { get; set; } = 1.0f;
	[Export] public float TerrainHeightVariation { get; set; } = 16.0f;

	[ExportGroup("Generation Control")]
	[Export]
	public bool WorldActive
	{
		get => _worldActive;
		set => SetWorldActive(value);
	}
	[Export] public bool AutoGenerateOnReady { get; set; } = true;

	[ExportGroup("Noise Settings")]
	[Export] public FastNoiseLite PrimaryBiomeNoise { get; set; }
	[Export] public FastNoiseLite SecondaryBiomeNoise { get; set; }
	[Export] public FastNoiseLite HeightNoise { get; set; }
	[Export] public bool AutoCreateDefaultNoise { get; set; } = true;

	[ExportSubgroup("Noise Mixing")]
	[Export(PropertyHint.Range, "0.0,1.0")] public float PrimaryNoiseWeight { get; set; } = 0.75f;
	[Export(PropertyHint.Range, "0.0,1.0")] public float SecondaryNoiseWeight { get; set; } = 0.25f;
	[Export(PropertyHint.Range, "0.0,2.0")] public float NoiseContrast { get; set; } = 1.0f;

	[ExportGroup("Height Settings")]
	[Export] public bool EnableHeightVariation { get; set; } = true;
	[Export(PropertyHint.Range, "0.0,1.0")] public float HeightInfluence { get; set; } = 1.0f;

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
	[Export] public bool CacheEnabled { get; set; } = true;

	[Export] public Node3D Player { get; set; }
	#endregion

	#region Private Fields
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
	#endregion

	public override void _Ready()
	{
		SetupBiomes();
		SetupNoise();
		CreateSaveDirectory();

		if (Engine.IsEditorHint())
		{
			FindPlayerOrCamera();
		}
		else
		{
			_camera = GetViewport().GetCamera3D();
			if (Player == null)
				FindPlayerOrCamera();
		}

		_threadSemaphore = new SemaphoreSlim(MaxConcurrentThreads, MaxConcurrentThreads);
		_cancellationTokenSource = new CancellationTokenSource();

		if (AutoGenerateOnReady)
			WorldActive = true;
	}

	public override void _ExitTree()
	{
		WorldActive = false;
		_cancellationTokenSource?.Cancel();
		_threadSemaphore?.Dispose();
		SaveAllDirtyChunks();
	}

	public override void _Process(double delta)
	{
		if (!_worldActive) return;

		if (Player != null)
		{
			var playerChunk = WorldToChunk(Player.GlobalPosition);
			if (playerChunk != _lastPlayerChunk)
			{
				_lastPlayerChunk = playerChunk;
				UpdateChunks();
			}
		}

		ProcessMeshCreationQueue();

		if (EnableFrustumCulling && _camera != null)
			UpdateChunkVisibility();
	}

	private void SetWorldActive(bool value)
	{
		if (_worldActive == value) return;
		_worldActive = value;

		if (_worldActive)
			UpdateChunks();
		else
			ClearWorld();
	}

	private void SetupBiomes()
	{
		_biomeColors = new[] { Color1, Color2, Color3, Color4, Color5, Color6, Color7, Color8 };
		_biomeThresholds = new[] { Threshold1, Threshold2, Threshold3, Threshold4, Threshold5, Threshold6, Threshold7 };
	}

	private void SetupNoise()
	{
		if (!AutoCreateDefaultNoise) return;

		PrimaryBiomeNoise ??= CreateDefaultNoise(0.02f, 2);
		SecondaryBiomeNoise ??= CreateDefaultNoise(0.05f, 1);
		if (EnableHeightVariation && HeightNoise == null)
			HeightNoise = CreateDefaultNoise(0.08f, 2);
	}

	private FastNoiseLite CreateDefaultNoise(float frequency, int octaves)
	{
		var noise = new FastNoiseLite
		{
			NoiseType = FastNoiseLite.NoiseTypeEnum.Perlin,
			Frequency = frequency,
			FractalType = FastNoiseLite.FractalTypeEnum.Fbm,
			FractalOctaves = octaves,
			Seed = GD.Randi()
		};
		return noise;
	}

	private void CreateSaveDirectory()
	{
		var dir = DirAccess.Open("user://");
		if (dir == null)
		{
			GD.PushError("Failed to open user:// directory for saving.");
			return;
		}

		var pathToCreate = SavePath.Replace("res://", "");
		if (!dir.DirExists(pathToCreate))
		{
			var err = dir.MakeDirRecursive(pathToCreate);
			if (err != Error.Ok)
				GD.PushError($"Could not create directory: user://{pathToCreate}");
		}
	}

	private void FindPlayerOrCamera()
	{
		if (Player != null) return;
		
		var p = GetTree().GetFirstNodeInGroup("player");
		if (p is Node3D player)
			Player = player;
		else if (GetViewport().GetCamera3D() != null)
			Player = GetViewport().GetCamera3D();
	}

	private void UpdateChunks()
	{
		if (Player == null) return;

		var playerChunkPos = WorldToChunk(Player.GlobalPosition);
		var chunksToLoad = new Dictionary<Vector2I, float>();

		for (int x = playerChunkPos.X - RenderDistance; x <= playerChunkPos.X + RenderDistance; x++)
		{
			for (int z = playerChunkPos.Y - RenderDistance; z <= playerChunkPos.Y + RenderDistance; z++)
			{
				var chunkCoord = new Vector2I(x, z);
				if (!_loadedChunks.ContainsKey(chunkCoord) && !_loadingChunks.Contains(chunkCoord))
				{
					float distSq = playerChunkPos.DistanceSquaredTo(chunkCoord);
					chunksToLoad[chunkCoord] = distSq;
				}
			}
		}

		var sortedChunks = new List<Vector2I>(chunksToLoad.Keys);
		sortedChunks.Sort((a, b) => chunksToLoad[a].CompareTo(chunksToLoad[b]));

		_generationQueue.Clear();
		foreach (var chunk in sortedChunks)
			_generationQueue.Enqueue(chunk);

		ProcessGenerationQueue();

		var chunksToUnload = new List<Vector2I>();
		foreach (var chunkCoord in _loadedChunks.Keys)
		{
			int dist = Math.Max(Math.Abs(chunkCoord.X - playerChunkPos.X), Math.Abs(chunkCoord.Y - playerChunkPos.Y));
			if (dist > UnloadDistance)
				chunksToUnload.Add(chunkCoord);
		}

		foreach (var coord in chunksToUnload)
			UnloadChunk(coord);
	}

	private void ProcessGenerationQueue()
	{
		while (_generationQueue.Count > 0)
		{
			var chunkCoord = _generationQueue.Dequeue();
			if (!_loadedChunks.ContainsKey(chunkCoord) && !_loadingChunks.Contains(chunkCoord))
			{
				LoadChunkAsync(chunkCoord);
			}
		}
	}

	private void ProcessMeshCreationQueue()
	{
		int processed = 0;
		while (processed < MaxChunksPerFrame && _meshCreationQueue.TryDequeue(out var chunkData))
		{
			CreateChunkObject(chunkData);
			processed++;
		}
	}

	private void UpdateChunkVisibility()
	{
		if (_camera == null) return;

		var frustumPlanes = _camera.GetFrustum();
		float chunkWorldSize = ChunkSize * PixelSize;

		foreach (var chunk in _loadedChunks.Values)
		{
			var chunkWorldPos = ChunkToWorld(chunk.ChunkCoord);
			var bounds = new Aabb(
				new Vector3(chunkWorldPos.X, -TerrainHeightVariation, chunkWorldPos.Y),
				new Vector3(chunkWorldSize, TerrainHeightVariation * 2, chunkWorldSize)
			);

			bool isVisible = true;
			foreach (var plane in frustumPlanes)
			{
				if (plane.IsPointOver(bounds.GetCenter()) && 
					plane.DistanceTo(bounds.GetCenter()) > bounds.Size.Length() * 0.5f)
				{
					isVisible = false;
					break;
				}
			}

			chunk.MeshInstance.Visible = isVisible;
		}
	}

	private async void LoadChunkAsync(Vector2I chunkCoord)
	{
		_loadingChunks.Add(chunkCoord);

		if (UseMultithreading)
		{
			await _threadSemaphore.WaitAsync(_cancellationTokenSource.Token);
			
			try
			{
				var chunkData = await Task.Run(() => GenerateChunkThreaded(chunkCoord), _cancellationTokenSource.Token);
				CallDeferred(nameof(OnChunkGenerated), chunkData);
			}
			catch (OperationCanceledException)
			{
				// Generation was cancelled
			}
			finally
			{
				_threadSemaphore.Release();
			}
		}
		else
		{
			var chunkData = GenerateChunkThreaded(chunkCoord);
			OnChunkGenerated(chunkData);
		}
	}

	private ChunkData GenerateChunkThreaded(Vector2I chunkCoord)
	{
		ChunkData chunkData = null;

		if (CacheEnabled)
			chunkData = TerrainChunk.LoadFromFile(chunkCoord, SavePath);

		if (chunkData == null)
		{
			chunkData = TerrainChunk.Generate(
				chunkCoord, ChunkSize, PixelSize,
				PrimaryBiomeNoise, SecondaryBiomeNoise, HeightNoise,
				_biomeColors, _biomeThresholds,
				EnableHeightVariation, HeightInfluence, TerrainHeightVariation,
				PrimaryNoiseWeight, SecondaryNoiseWeight, NoiseContrast
			);
			chunkData.IsDirty = true;
		}

		return chunkData;
	}

	private void OnChunkGenerated(ChunkData chunkData)
	{
		if (!_worldActive) return;
		_meshCreationQueue.Enqueue(chunkData);
	}

	private void CreateChunkObject(ChunkData chunkData)
	{
		var chunkCoord = chunkData.ChunkCoord;
		_loadingChunks.Remove(chunkCoord);

		if (_loadedChunks.ContainsKey(chunkCoord) || !_worldActive)
			return;

		var chunk = new TerrainChunk(chunkCoord, chunkData);
		chunk.CreateMesh(ChunkSize, PixelSize, CustomMaterial);

		var worldPos = ChunkToWorld(chunkCoord);
		chunk.MeshInstance.Position = new Vector3(worldPos.X, 0, worldPos.Y);

		AddChild(chunk.MeshInstance);
		_loadedChunks[chunkCoord] = chunk;
	}

	private void UnloadChunk(Vector2I chunkCoord)
	{
		if (_loadedChunks.TryGetValue(chunkCoord, out var chunk))
		{
			if (chunk.IsDirty && CacheEnabled)
				chunk.SaveToFile(SavePath);
			
			chunk.MeshInstance.QueueFree();
			_loadedChunks.Remove(chunkCoord);
		}
	}

	private void ClearWorld()
	{
		foreach (var chunkCoord in new List<Vector2I>(_loadedChunks.Keys))
			UnloadChunk(chunkCoord);

		_loadedChunks.Clear();
		_loadingChunks.Clear();
		_generationQueue.Clear();
		_meshCreationQueue = new ConcurrentQueue<ChunkData>();
	}

	private void SaveAllDirtyChunks()
	{
		foreach (var chunk in _loadedChunks.Values)
		{
			if (chunk.IsDirty)
				chunk.SaveToFile(SavePath);
		}
	}

	private Vector2I WorldToChunk(Vector3 worldPos)
	{
		float chunkWorldSize = ChunkSize * PixelSize;
		return new Vector2I(
			Mathf.FloorToInt(worldPos.X / chunkWorldSize),
			Mathf.FloorToInt(worldPos.Z / chunkWorldSize)
		);
	}

	private Vector2 ChunkToWorld(Vector2I chunkCoord)
	{
		float chunkWorldSize = ChunkSize * PixelSize;
		return new Vector2(chunkCoord.X * chunkWorldSize, chunkCoord.Y * chunkWorldSize);
	}
}
