// Cold Streets: server-verified Supabase Auth identity and player ownership.
// All protected routes MUST run requireAuthenticatedPlayer before their handlers.
// Never trust a client-supplied user_id / userId to establish identity.
const pool = require('../db');
const logger = require('../utils/logger');

const AUTH_TIMEOUT_MS = 10000;
const AUTH_MAX_IN_FLIGHT = 50;
let authVerificationsInFlight = 0;

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const PLAYER_ID_PATTERN = /^[1-9][0-9]*$/;

function authConfiguration() {
    const projectUrl = process.env.SUPABASE_URL;
    const key = process.env.SUPABASE_PUBLISHABLE_KEY;
    if (!projectUrl || !key) return null;
    try {
        const url = new URL(projectUrl);
        if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash ||
            (url.pathname !== '/' && url.pathname !== '')) return null;
        return { endpoint: new URL('/auth/v1/user', url).toString(), key };
    } catch {
        return null;
    }
}

function playerIdString(value) {
    if (typeof value === 'number') {
        return Number.isSafeInteger(value) && value > 0 ? String(value) : null;
    }
    if (typeof value === 'string' && PLAYER_ID_PATTERN.test(value)) return value;
    return null;
}

function assertOwnedId(req, supplied) {
    const requested = playerIdString(supplied);
    if (!requested) return { status: 400, message: 'Invalid player ID.' };
    if (!req.player || requested !== String(req.player.userId)) {
        return { status: 403, message: 'You cannot access another player account.' };
    }
    return null;
}

// Auth server verifies tokens regardless of whether the project uses asymmetric
// signing keys or the legacy shared-secret signing setup. Decoding alone is NOT
// verification. No secret/service-role key is needed or accepted here.
async function requireSupabaseIdentity(req, res, next) {
    const config = authConfiguration();
    if (!config) {
        return res.status(503).json({ error: 'Authentication is not configured on the API.' });
    }

    const header = req.headers.authorization;
    const match = typeof header === 'string' && /^Bearer ([a-zA-Z0-9._~+/-]+=*)$/i.exec(header);
    if (!match || match[1].length > 8192) {
        return res.status(401).json({ error: 'A Supabase access token is required.' });
    }
    if (authVerificationsInFlight >= AUTH_MAX_IN_FLIGHT) {
        res.setHeader('Retry-After', '1');
        logger.warn('auth_upstream_backpressure', {
            request_id: req.requestId,
            in_flight: authVerificationsInFlight
        });
        return res.status(503).json({
            error: 'Authentication service is temporarily busy. Retry shortly.'
        });
    }

    authVerificationsInFlight += 1;
    try {
        const response = await fetch(config.endpoint, {
            method: 'GET',
            headers: {
                apikey: config.key,
                Authorization: `Bearer ${match[1]}`
            },
            signal: AbortSignal.timeout(AUTH_TIMEOUT_MS)
        });

        if (response.status === 401 || response.status === 403 || response.status === 400) {
            return res.status(401).json({ error: 'Invalid or expired Supabase session.' });
        }
        if (!response.ok) {
            return res.status(503).json({ error: 'Unable to verify the session.' });
        }

        const user = await response.json();
        if (!user || !UUID_PATTERN.test(user.id || '') ||
            typeof user.email !== 'string' || !user.email.trim() || user.is_anonymous === true) {
            return res.status(403).json({ error: 'A verified, non-anonymous email account is required.' });
        }

        req.authIdentity = {
            uid: user.id,
            email: user.email.trim().toLowerCase(),
            emailConfirmed: Boolean(user.email_confirmed_at || user.confirmed_at)
        };
        return next();
    } catch (err) {
        logger.error('auth_verification_failed', {
            request_id: req.requestId,
            ...logger.errorFields(err)
        });
        return res.status(503).json({ error: 'Authentication service unavailable.' });
    } finally {
        authVerificationsInFlight -= 1;
    }
}

async function requireAuthenticatedPlayer(req, res, next) {
    await requireSupabaseIdentity(req, res, async () => {
        try {
            const result = await pool.query(
                'SELECT user_id FROM public.users WHERE supabase_auth_uid = $1 LIMIT 1',
                [req.authIdentity.uid]
            );
            if (result.rows.length !== 1) {
                return res.status(403).json({
                    error: 'Player profile not found. Complete /auth/session first.'
                });
            }
            req.player = { userId: String(result.rows[0].user_id), authUid: req.authIdentity.uid };

            // All current request-body/query actor identifiers are validated
            // before any protected handler runs. Resource IDs (target_id,
            // crew_id, company_id, etc.) have separate authorization rules.
            for (const source of [req.body, req.query]) {
                if (!source || typeof source !== 'object') continue;
                for (const name of ['user_id', 'userId']) {
                    if (!Object.prototype.hasOwnProperty.call(source, name)) continue;
                    const error = assertOwnedId(req, source[name]);
                    if (error) return res.status(error.status).json({ error: error.message });
                }
            }
            return next();
        } catch (err) {
            logger.error('player_identity_lookup_failed', {
                request_id: req.requestId,
                ...logger.errorFields(err)
            });
            return res.status(503).json({ error: 'Unable to resolve player identity.' });
        }
    });
}

// Express router.param callbacks execute AFTER route matching, so they validate
// /:user_id and /:userId where app.use() pre-router middleware cannot.
function requireOwnedPlayerParam(req, res, next, supplied) {
    const error = assertOwnedId(req, supplied);
    if (error) return res.status(error.status).json({ error: error.message });
    return next();
}

module.exports = {
    requireSupabaseIdentity,
    requireAuthenticatedPlayer,
    requireOwnedPlayerParam
};
