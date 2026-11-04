const { randomInt } = require('node:crypto');
const { completeIdempotent } = require('./idempotency');

function randomPercent() {
    return randomInt(0, 1000000) / 10000;
}

function randomInclusive(minValue, maxValue) {
    const min = Number(minValue ?? 0);
    const max = Number(maxValue ?? 0);
    if (!Number.isSafeInteger(min) || !Number.isSafeInteger(max) || min > max) {
        throw new Error('Crime reward range is not a valid safe integer interval.');
    }
    if (min === max) return min;
    return randomInt(min, max + 1);
}

function randomText(values, fallback = 'The streets are silent.') {
    if (!Array.isArray(values) || values.length === 0) return fallback;
    return values[randomInt(0, values.length)];
}

async function commitCrimeOutcome(client, req, res, response, afterCommit = null) {
    if (!req.crimeIdempotency || req.crimeIdempotency.replay) {
        throw new Error('Crime idempotency context is missing.');
    }
    await completeIdempotent(client, req.crimeIdempotency, 200, response);
    await client.query('COMMIT');
    if (typeof afterCommit === 'function') {
        try {
            afterCommit();
        } catch (error) {
            console.error('Post-commit crime side effect failed:', error);
        }
    }
    return res.json(response);
}

module.exports = {
    randomPercent,
    randomInclusive,
    randomText,
    commitCrimeOutcome
};
