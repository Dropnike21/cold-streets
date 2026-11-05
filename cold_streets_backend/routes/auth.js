const express = require('express');
const pool = require('../db');
const {
    requireSupabaseIdentity,
    requireAuthenticatedPlayer,
    requireOwnedPlayerParam
} = require('../middleware/playerIdentity');

const router = express.Router();

// The previous password-only routes did not produce a verified session and
// cannot safely authorize the game. New players register/sign in with Supabase
// Auth (Flutter SDK), then POST their bearer token to /auth/session.
function legacyAuthenticationDisabled(req, res) {
    return res.status(410).json({
        error: 'Legacy passwords are no longer accepted by the game API. Sign in with Supabase Auth.'
    });
}
router.post('/register', legacyAuthenticationDisabled);
router.post('/login', legacyAuthenticationDisabled);

const PROFILE_FIELDS = `
    user_id, username, role, level, exp, crime_exp, contact_exp, active_contract,
    dirty_cash, clean_cash, casino_tokens, energy, hp, nerve, max_nerve,
    heat, jail_expires_at, hospital_expires_at, stat_str, stat_def, stat_dex,
    stat_spd, influence, has_bazaar, cred, stat_acu, stat_ops, stat_pre, stat_res
`;

// Establishes a new internal integer player record for a *verified* Supabase
// identity, or returns the existing mapped profile. Email comes ONLY from the
// Auth server. Client metadata never controls roles, ownership or account IDs.
router.post('/session', requireSupabaseIdentity, async (req, res) => {
    const { uid, email, emailConfirmed } = req.authIdentity;
    const supplied = req.body && req.body.username;
    const username = typeof supplied === 'string' ? supplied.trim() : '';
    let client;
    let inTransaction = false;

    try {
        client = await pool.connect();
        await client.query('BEGIN');
        inTransaction = true;

        const prior = await client.query(
            'SELECT user_id FROM public.users WHERE supabase_auth_uid = $1 FOR UPDATE',
            [uid]
        );
        let newPlayer = false;
        let userId = prior.rows[0]?.user_id;

        if (!userId) {
            if (!emailConfirmed) {
                throw Object.assign(new Error('Confirm your email before creating a game account.'), { status: 403 });
            }
            if (!/^[a-zA-Z0-9_]{3,24}$/.test(username)) {
                throw Object.assign(new Error('Street name must contain 3-24 letters, numbers or underscores.'), { status: 400 });
            }

            // Prevent partially configured players from being created while
            // the recovered starter catalog is still missing from Supabase.
            const starterGym = await client.query('SELECT 1 FROM gyms_master WHERE gym_id = 1');
            if (starterGym.rowCount !== 1) {
                throw Object.assign(new Error('Game catalogs are still being restored; new player creation is unavailable.'), { status: 503 });
            }
            const starterProperty = await client.query('SELECT 1 FROM properties_master WHERE id = 1 AND cost = 0');
            if (starterProperty.rowCount !== 1) {
                throw Object.assign(new Error('Starter property catalog is unavailable; account creation is temporarily disabled.'), { status: 503 });
            }

            // Use only a verified subject + email. Do NOT auto-link older
            // password accounts solely by matching email; that requires
            // an explicit, verified migration/recovery process.
            const created = await client.query(
                `INSERT INTO public.users (supabase_auth_uid, email, username, role)
                 VALUES ($1, $2, $3, 'player')
                 ON CONFLICT DO NOTHING
                 RETURNING user_id`,
                [uid, email, username]
            );
            if (created.rows.length) {
                newPlayer = true;
                userId = created.rows[0].user_id;

                await client.query('INSERT INTO user_equipment (user_id) VALUES ($1)', [userId]);
                await client.query('INSERT INTO user_properties (user_id) VALUES ($1)', [userId]);
                await client.query('INSERT INTO user_crime_records (user_id) VALUES ($1)', [userId]);
                await client.query('INSERT INTO user_statistics (user_id) VALUES ($1)', [userId]);
                await client.query(
                    'INSERT INTO user_gym_stats (user_id, active_gym_id, gym_exp) VALUES ($1, 1, 0)',
                    [userId]
                );
                await client.query(
                    'INSERT INTO user_owned_gyms (user_id, gym_id) VALUES ($1, 1)',
                    [userId]
                );
                // Exactly one initial residence is granted at verified profile
                // creation, never by visiting a GET endpoint.
                const starterResidence = await client.query(
                    "INSERT INTO owned_properties (user_id, property_type_id, status) VALUES ($1, 1, 'active_residence') RETURNING id",
                    [userId]
                );
                await client.query(
                    `INSERT INTO property_transactions
                        (instance_id, seller_id, buyer_id, transaction_type, amount)
                     VALUES ($1, NULL, $2, 'STARTER_GRANT', 0)`,
                    [starterResidence.rows[0].id, userId]
                );
                await client.query(
                    'INSERT INTO user_events (user_id, event_text) VALUES ($1, $2)',
                    [userId, 'Welcome to Cold Streets. Check your burner phone for instructions.']
                );
            } else {
                const concurrent = await client.query(
                    'SELECT user_id FROM public.users WHERE supabase_auth_uid = $1',
                    [uid]
                );
                if (!concurrent.rows.length) {
                    throw Object.assign(new Error('Street name or email is already in use. Legacy account recovery requires manual review.'), { status: 409 });
                }
                userId = concurrent.rows[0].user_id;
            }
        }

        const profile = await client.query(
            `SELECT ${PROFILE_FIELDS} FROM public.users WHERE user_id = $1`,
            [userId]
        );
        if (profile.rows.length !== 1) throw new Error('Player profile could not be resolved.');

        await client.query('COMMIT');
        inTransaction = false;
        return res.json({
            message: newPlayer ? 'Welcome to the Syndicate.' : 'Authentication successful.',
            user: profile.rows[0]
        });
    } catch (err) {
        if (client && inTransaction) {
            try { await client.query('ROLLBACK'); } catch (rollbackError) {
                console.error('Profile rollback failed:', rollbackError.message);
            }
        }
        if (err.status) return res.status(err.status).json({ error: err.message });
        console.error('Session profile error:', err.message);
        return res.status(503).json({ error: 'Unable to initialize player profile.' });
    } finally {
        if (client) client.release();
    }
});

// All subsequent routes must resolve the trusted player before reading data.
router.use(requireAuthenticatedPlayer);
router.param('user_id', requireOwnedPlayerParam);

router.get('/status/:user_id', async (req, res) => {
    try {
        const { user_id } = req.params;
        const userQuery = await pool.query(
            `SELECT dirty_cash, clean_cash, cred, energy, nerve, max_nerve,
                    hp, level, exp, crime_exp, heat, contact_exp, active_contract,
                    jail_expires_at, hospital_expires_at
             FROM public.users WHERE user_id = $1`,
            [user_id]
        );
        if (!userQuery.rows.length) return res.status(404).json({ error: 'Player not found.' });

        const cdQuery = await pool.query(
            `SELECT type, EXTRACT(EPOCH FROM (expires_at - NOW())) AS seconds_left
             FROM user_cooldowns WHERE user_id = $1 AND expires_at > NOW()`,
            [user_id]
        );
        return res.json({ user: userQuery.rows[0], cooldowns: cdQuery.rows });
    } catch (err) {
        console.error('Status sync failed:', err.message);
        return res.status(503).json({ error: 'Unable to load player status.' });
    }
});

module.exports = router;
