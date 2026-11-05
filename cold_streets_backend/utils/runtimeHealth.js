const REQUIRED_WORKERS = ['state_duration'];

const state = {
    startedAt: new Date(),
    gameplayEnabled: false,
    databaseReady: false,
    databaseLastFailureAt: null,
    shuttingDown: false,
    workers: Object.create(null)
};

function configure({ gameplayEnabled }) {
    state.gameplayEnabled = Boolean(gameplayEnabled);
}

function markDatabaseReady() {
    state.databaseReady = true;
    state.databaseLastFailureAt = null;
}

function markDatabaseFailure() {
    state.databaseReady = false;
    state.databaseLastFailureAt = new Date();
}

function markWorkerStarted(name) {
    state.workers[name] = {
        started: true,
        healthy: true,
        lastPollAt: null,
        lastSuccessAt: null,
        lastFailureAt: null,
        lastSettledCount: 0
    };
}

function markWorkerPollSuccess(name, settledCount = 0) {
    const worker = state.workers[name] || {};
    worker.started = true;
    worker.healthy = true;
    worker.lastPollAt = new Date();
    worker.lastSuccessAt = worker.lastPollAt;
    worker.lastSettledCount = Number.isSafeInteger(settledCount) ? settledCount : 0;
    state.workers[name] = worker;
}

function markWorkerPollFailure(name) {
    const worker = state.workers[name] || {};
    worker.started = true;
    worker.healthy = false;
    worker.lastPollAt = new Date();
    worker.lastFailureAt = worker.lastPollAt;
    state.workers[name] = worker;
}

function markWorkerStopped(name) {
    const worker = state.workers[name] || {};
    worker.started = false;
    worker.healthy = false;
    state.workers[name] = worker;
}

function markShuttingDown() {
    state.shuttingDown = true;
}

function snapshot() {
    const workers = {};
    for (const name of REQUIRED_WORKERS) {
        const worker = state.workers[name] || {};
        workers[name] = {
            started: worker.started === true,
            healthy: worker.healthy === true,
            last_poll_at: worker.lastPollAt ? worker.lastPollAt.toISOString() : null,
            last_success_at: worker.lastSuccessAt ? worker.lastSuccessAt.toISOString() : null,
            last_failure_at: worker.lastFailureAt ? worker.lastFailureAt.toISOString() : null,
            last_settled_count: worker.lastSettledCount || 0
        };
    }

    const workersReady = !state.gameplayEnabled || REQUIRED_WORKERS.every(name => {
        const worker = state.workers[name];
        return worker && worker.started === true && worker.healthy === true;
    });

    const ready = !state.shuttingDown &&
        (!state.gameplayEnabled || (state.databaseReady && workersReady));

    return {
        ready,
        gameplay_enabled: state.gameplayEnabled,
        shutting_down: state.shuttingDown,
        database_ready: state.gameplayEnabled ? state.databaseReady : null,
        database_last_failure_at: state.databaseLastFailureAt
            ? state.databaseLastFailureAt.toISOString()
            : null,
        workers: state.gameplayEnabled ? workers : {},
        uptime_seconds: Math.max(
            0,
            Math.floor((Date.now() - state.startedAt.getTime()) / 1000)
        )
    };
}

module.exports = {
    configure,
    markDatabaseReady,
    markDatabaseFailure,
    markWorkerStarted,
    markWorkerPollSuccess,
    markWorkerPollFailure,
    markWorkerStopped,
    markShuttingDown,
    snapshot
};
