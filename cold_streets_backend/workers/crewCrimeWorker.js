const PAUSE_REASON =
    'Crew crime automation is paused because Recruits Canvas conflicts with crimes_master on loop timing and mortality semantics.';

async function settleOneDueCrewCrime() {
    throw new Error(PAUSE_REASON);
}

async function settleDueCrewCrimeBatch() {
    throw new Error(PAUSE_REASON);
}

function startCrewCrimeWorker() {
    throw new Error(PAUSE_REASON);
}

module.exports = {
    settleOneDueCrewCrime,
    settleDueCrewCrimeBatch,
    startCrewCrimeWorker
};
