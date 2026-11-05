const logger = require('./logger');
const {
  classifyOperationalError,
  applyOperationalResponse
} = require('./operationalErrors');
// Shared money validation for server-authoritative transactions.
// node-postgres returns NUMERIC as strings; avoid JS Number for ledger math.
class ActionError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}
const MAX_MONEY = 999999999999999999999999n; // NUMERIC(24,0)
const SAFE_INTEGER = BigInt(Number.MAX_SAFE_INTEGER);

function integer(value, { field = 'Value', min = 0n, max = MAX_MONEY } = {}) {
  let parsed;
  if (typeof value === 'number') {
    if (!Number.isSafeInteger(value)) throw new ActionError(400, field + ' must be an exact integer.');
    parsed = BigInt(value);
  } else if (typeof value === 'string' && /^(?:0|[1-9][0-9]*)$/.test(value)) {
    parsed = BigInt(value);
  } else {
    throw new ActionError(400, field + ' must be an exact integer.');
  }
  if (parsed < min || parsed > max) throw new ActionError(400, field + ' is outside permitted limits.');
  return parsed;
}
function dbInteger(value, { field = 'Database amount' } = {}) {
  if (value === null || value === undefined) throw new Error(field + ' is absent from database.');
  const text = String(value);
  if (!/^-?(?:0|[1-9][0-9]*)(?:\.0+)?$/.test(text)) {
    throw new Error(field + ' must be an integer-denominated amount.');
  }
  return BigInt(text.split('.')[0]);
}
function exactJsonAmount(n) {
  return n <= SAFE_INTEGER && n >= -SAFE_INTEGER ? Number(n) : n.toString();
}
function actorId(req) {
  if (!req.player?.userId) throw new ActionError(401, 'Authentication required.');
  return integer(req.player.userId, { field: 'Authenticated player ID', min: 1n, max: SAFE_INTEGER }).toString();
}
function sendActionError(res, error, context) {
  if (error instanceof ActionError) return res.status(error.status).json({ error: error.message });

  const operational = classifyOperationalError(error);
  if (operational) {
    logger.warn('action_operational_failure', {
      request_id: res.req?.requestId,
      context,
      operational_kind: operational.kind,
      ...logger.errorFields(error)
    });
    return applyOperationalResponse(res, operational);
  }

  logger.error('action_failed', {
    request_id: res.req?.requestId,
    context,
    ...logger.errorFields(error)
  });
  return res.status(500).json({ error: 'Transaction could not be completed.' });
}
module.exports = { ActionError, integer, dbInteger, exactJsonAmount, actorId, sendActionError, MAX_MONEY, SAFE_INTEGER };
