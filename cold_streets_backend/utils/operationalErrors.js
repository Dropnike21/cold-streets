// Classify transient infrastructure failures without exposing PostgreSQL/network
// details to API clients. These errors are safe to retry; business-rule and
// validation failures are handled elsewhere.
const RETRYABLE_POSTGRES_CODES = new Set([
    '40001', // serialization_failure
    '40P01', // deadlock_detected
    '53300', // too_many_connections
    '53400', // configuration_limit_exceeded
    '55P03', // lock_not_available / lock_timeout
    '57014', // query_canceled / statement_timeout
    '57P01', // admin_shutdown
    '57P02', // crash_shutdown
    '57P03', // cannot_connect_now
    '57P05'  // idle_session_timeout
]);

const RETRYABLE_NETWORK_CODES = new Set([
    'ECONNREFUSED',
    'ECONNRESET',
    'ETIMEDOUT',
    'EHOSTUNREACH',
    'ENETUNREACH',
    'EPIPE',
    'EAI_AGAIN'
]);

function classifyOperationalError(error) {
    if (!error) return null;

    const code = error.code === undefined || error.code === null
        ? ''
        : String(error.code);
    const message = String(error.message || '');

    if (
        code.startsWith('08') ||
        RETRYABLE_POSTGRES_CODES.has(code) ||
        RETRYABLE_NETWORK_CODES.has(code)
    ) {
        return {
            kind: code === '55P03' || code === '57014' ||
                code === '40001' || code === '40P01'
                ? 'database_contention_or_timeout'
                : 'database_unavailable',
            status: 503,
            retryAfterSeconds: 1,
            publicMessage: 'Service temporarily unavailable. Retry the request.'
        };
    }

    // node-postgres may surface pool-acquisition/query timeouts without a stable
    // SQLSTATE. Keep the message matching deliberately narrow.
    if (
        /timeout exceeded when trying to connect/i.test(message) ||
        /connection terminated unexpectedly/i.test(message) ||
        /connection terminated due to connection timeout/i.test(message) ||
        /query read timeout/i.test(message)
    ) {
        return {
            kind: 'database_timeout',
            status: 503,
            retryAfterSeconds: 1,
            publicMessage: 'Service temporarily unavailable. Retry the request.'
        };
    }

    return null;
}

function applyOperationalResponse(res, classification) {
    res.setHeader('Retry-After', String(classification.retryAfterSeconds));
    res.setHeader('Cache-Control', 'no-store');
    return res.status(classification.status).json({
        error: classification.publicMessage
    });
}

module.exports = {
    classifyOperationalError,
    applyOperationalResponse
};
