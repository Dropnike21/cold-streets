const { randomUUID } = require('node:crypto');
const logger = require('../utils/logger');

const REQUEST_ID_PATTERN =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const UUID_SEGMENT =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function safePath(req) {
    const raw = (req.originalUrl || req.url || '/').split('?')[0];
    return raw.split('/').map(segment => {
        if (/^[1-9][0-9]*$/.test(segment)) return ':id';
        if (UUID_SEGMENT.test(segment)) return ':uuid';
        return segment.length > 80 ? ':segment' : segment;
    }).join('/');
}

function requestObservability(req, res, next) {
    const incoming = req.headers['x-request-id'];
    req.requestId =
        typeof incoming === 'string' && REQUEST_ID_PATTERN.test(incoming)
            ? incoming.toLowerCase()
            : randomUUID();

    res.setHeader('X-Request-Id', req.requestId);
    const started = process.hrtime.bigint();

    res.once('finish', () => {
        const elapsedNs = process.hrtime.bigint() - started;
        const durationMs = Number(elapsedNs / 1000000n);
        const fields = {
            request_id: req.requestId,
            method: req.method,
            path: safePath(req),
            status: res.statusCode,
            duration_ms: durationMs,
            authenticated_player: Boolean(req.player)
        };
        if (res.statusCode >= 500) logger.error('http_request', fields);
        else if (res.statusCode >= 400) logger.warn('http_request', fields);
        else logger.info('http_request', fields);
    });

    next();
}

module.exports = requestObservability;
