// routes/crimes.js
const logger = require('../utils/logger');
const express = require('express');
const pool = require('../db');
const router = express.Router();
const {
    ActionError, actorId, integer, sendActionError
} = require('../utils/economyValidation');
const { requireIdempotencyKey, beginIdempotent } = require('../utils/idempotency');

// --- IMPORT YOUR SPECIFIC CRIME MODULES HERE ---
const searchingEngine = require('./crimes/searching_engine');
const shopliftingEngine = require('./crimes/shoplifting');
const pickpocketEngine = require('./crimes/pickpocketing');

router.get('/list', async (req, res) => {
    const type = req.query.type;

    // 🚨 THIS IS THE MISSING PIECE! 🚨
    // Catch Pickpocketing requests and route to the custom fetcher
    if (type === 'pickpocketing') {
        const client = await pool.connect();
        try {
            return await pickpocketEngine.listTargets(client, res);
        } finally {
            client.release();
        }
    }

    // Default Fetcher (Used by The Streets Job Board and Shoplifting)
    try {
        const crimes = await pool.query("SELECT * FROM crimes_master ORDER BY req_skill_level ASC, id ASC");
        res.json(crimes.rows);
    } catch (err) {
        logger.error('crimes_fetch_failed', logger.errorFields(err));
        res.status(500).json({ error: "Failed to load Job Board." });
    }
});

router.post('/execute', async (req, res) => {
    let client;
    let transaction = false;

    try {
        const userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        const crimeId = integer(req.body?.crime_id, {
            field: 'Crime ID',
            min: 1n,
            max: 9223372036854775807n
        }).toString();

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        const userCheck = await client.query(
            'SELECT * FROM users WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (userCheck.rowCount !== 1) {
            throw new ActionError(404, 'Player not found.');
        }
        const user = userCheck.rows[0];

        const idem = await beginIdempotent(
            client,
            userId,
            'crimes.execute',
            idempotencyKey,
            { crimeId }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }
        req.crimeIdempotency = idem;

        const now = new Date();
        if (user.jail_expires_at && new Date(user.jail_expires_at) > now) {
            throw new ActionError(403, 'You are locked behind bars.');
        }
        if (user.hospital_expires_at &&
            new Date(user.hospital_expires_at) > now) {
            throw new ActionError(
                403,
                'You are recovering in the hospital.'
            );
        }
        if (Number(user.hp) < 25) {
            throw new ActionError(
                403,
                'You are too weak. Heal up to 25 HP first.'
            );
        }

        const crimeCheck = await client.query(
            'SELECT * FROM crimes_master WHERE id = $1',
            [crimeId]
        );
        if (crimeCheck.rowCount !== 1) {
            throw new ActionError(404, 'Crime not found.');
        }
        const crime = crimeCheck.rows[0];

        switch (crime.sub_category) {
            case 'Searching':
                return await searchingEngine.execute(
                    client, user, crime, req, res
                );

            case 'Shoplifting':
                return await shopliftingEngine.execute(
                    client, user, crime, req, res
                );

            case 'Pickpocketing':
                throw new ActionError(
                    503,
                    'Pickpocket execution is paused until target activity is server-issued.'
                );

            default:
                throw new ActionError(
                    400,
                    'Crime mechanics are not implemented for this category.'
                );
        }
    } catch (err) {
        if (client && transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) {
                // sendActionError records the primary failure. A rollback
                // failure is infrastructure-level and should not replace it.
            }
        }
        return sendActionError(res, err, 'Crime execution failed:');
    } finally {
        if (client) client.release();
    }
});
module.exports = router;