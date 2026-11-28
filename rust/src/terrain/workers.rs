use std::{
    collections::HashSet,
    sync::{Arc, Condvar, Mutex, mpsc},
    thread::{self, JoinHandle},
};

use super::{
    generator::{self, TerrainSettings},
    mesh::{self, MeshData},
};

const MAX_QUEUED_JOBS: usize = 96;

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub struct ChunkCoord {
    pub x: i32,
    pub z: i32,
}

#[derive(Clone, Copy)]
pub struct GenerationJob {
    pub seed: u32,
    pub coord: ChunkCoord,
    pub settings: TerrainSettings,
    pub revision: u64,
    pub priority: u64,
}

pub struct GenerationResult {
    pub seed: u32,
    pub coord: ChunkCoord,
    pub revision: u64,
    pub mesh: Arc<MeshData>,
}

struct QueueState {
    jobs: Vec<GenerationJob>,
    shutdown: bool,
}

struct SharedQueue {
    state: Mutex<QueueState>,
    available: Condvar,
}

pub struct WorkerPool {
    queue: Arc<SharedQueue>,
    results: mpsc::Receiver<GenerationResult>,
    handles: Vec<JoinHandle<()>>,
}

impl WorkerPool {
    pub fn new(worker_count: usize) -> Self {
        let queue = Arc::new(SharedQueue {
            state: Mutex::new(QueueState {
                jobs: Vec::new(),
                shutdown: false,
            }),
            available: Condvar::new(),
        });
        let (result_sender, results) = mpsc::channel();
        let worker_count = worker_count.clamp(1, 4);
        let mut handles = Vec::with_capacity(worker_count);

        for worker_index in 0..worker_count {
            let queue = Arc::clone(&queue);
            let result_sender = result_sender.clone();
            handles.push(
                thread::Builder::new()
                    .name(format!("gilo-terrain-{worker_index}"))
                    .spawn(move || worker_loop(queue, result_sender))
                    .expect("failed to create terrain worker"),
            );
        }

        Self {
            queue,
            results,
            handles,
        }
    }

    pub fn try_submit(&self, job: GenerationJob) -> bool {
        let mut state = self
            .queue
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.shutdown || state.jobs.len() >= MAX_QUEUED_JOBS {
            return false;
        }
        state.jobs.push(job);
        self.queue.available.notify_one();
        true
    }

    pub fn retain_queued(
        &self,
        revision: u64,
        required: &HashSet<(i32, i32)>,
    ) -> Vec<GenerationJob> {
        let mut state = self
            .queue
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let mut retained = Vec::with_capacity(state.jobs.len());
        let mut discarded = Vec::new();
        for job in state.jobs.drain(..) {
            if job.revision == revision && required.contains(&(job.coord.x, job.coord.z)) {
                retained.push(job);
            } else {
                discarded.push(job);
            }
        }
        state.jobs = retained;
        discarded
    }

    pub fn drain_results(&self) -> impl Iterator<Item = GenerationResult> + '_ {
        self.results.try_iter()
    }
}

impl Drop for WorkerPool {
    fn drop(&mut self) {
        {
            let mut state = self
                .queue
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.shutdown = true;
            state.jobs.clear();
        }
        self.queue.available.notify_all();
        for handle in self.handles.drain(..) {
            let _ = handle.join();
        }
    }
}

fn worker_loop(queue: Arc<SharedQueue>, results: mpsc::Sender<GenerationResult>) {
    loop {
        let job = {
            let mut state = queue
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            while state.jobs.is_empty() && !state.shutdown {
                state = queue
                    .available
                    .wait(state)
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
            }
            if state.shutdown {
                return;
            }
            let next_index = state
                .jobs
                .iter()
                .enumerate()
                .min_by_key(|(_, job)| job.priority)
                .map(|(index, _)| index)
                .expect("non-empty worker queue");
            state.jobs.swap_remove(next_index)
        };

        let data = generator::generate(job.seed, job.coord.x, job.coord.z, job.settings);
        let mesh = Arc::new(mesh::build_mesh_data(&data));
        if results
            .send(GenerationResult {
                seed: job.seed,
                coord: job.coord,
                revision: job.revision,
                mesh,
            })
            .is_err()
        {
            return;
        }
    }
}
