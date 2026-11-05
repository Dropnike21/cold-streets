const logger = require('../utils/logger');

const ACTIVE_MUTATION_FIELDS = new Map([
    ['POST /auth/session', ['username']],
    ['POST /bank/claim-check', ['check_id']],
    ['POST /character/level-up', ['action']],
    ['POST /companies/incorporation-preflight', ['type_id', 'company_name']],
    ['POST /companies/employment-offers/respond', ['offer_id', 'action']],
    ['POST /companies/apply', ['company_id', 'pitch_message']],

    ['POST /company-management/funds', ['company_id', 'amount']],
    ['POST /company-management/update-profile', ['company_id', 'company_name', 'logo_url']],
    ['POST /company-management/assign-crew', ['company_id', 'crew_id', 'position_id']],
    ['POST /company-management/recall-crew', ['company_id', 'crew_id']],
    ['POST /company-management/employment-offer', [
        'company_id', 'application_id', 'position_id', 'daily_salary_clean'
    ]],
    ['POST /company-management/employment-offer/withdraw', ['company_id', 'offer_id']],
    ['POST /company-management/manage-applicant', ['company_id', 'application_id', 'action']],

    ['POST /crimes/execute', ['crime_id']],
    ['POST /events/mark_read', []],
    ['POST /gym/purchase', ['gym_id']],
    ['POST /gym/activate', ['gym_id']],
    ['POST /gym/train', ['stat_type', 'energy_spent', 'gym_id']],
    ['POST /hospital/revive', ['target_id']],
    ['POST /info-broker/classifieds', ['ad_text']],
    ['POST /inventory/use', ['item_id']],
    ['POST /inventory/equip', ['item_id', 'slot']],

    ['POST /jobs/interview/submit', ['interview_id', 'answers']],
    ['POST /jobs/claim-daily', []],
    ['POST /jobs/promote', []],
    ['POST /jobs/quit', ['exit_type']],
    ['POST /jobs/mastery/activate', ['job_id']],

    ['POST /market/buy-bulk', ['cart']],
    ['POST /missions/tutorial/visit', ['visit']],
    ['POST /missions/action', ['contact', 'action_type']],
    ['POST /real-estate/move-in', ['instanceId']],

    ['POST /syndicate/assign_job', ['crew_id', 'crime_id']],
    ['POST /syndicate/unassign_job', ['crew_id']],
    ['POST /syndicate/generate_board', []],
    ['POST /syndicate/hire', ['offer_id']],

    ['POST /trade-network/listing-preflight', [
        'asset_namespace', 'item_id', 'pack_key', 'quantity'
    ]],

    ['POST /university/enroll', ['course_id']],
    ['POST /university/dropout', []],
    ['POST /university/graduate', []]
]);

const KNOWN_PAUSED_MUTATIONS = new Set([
    'POST /auth/register',
    'POST /auth/login',
    'POST /bank/deposit',
    'POST /bank/claim-deposit',
    'POST /companies/incorporate',
    'POST /company-management/manage-employee',
    'POST /company-management/change-director',
    'POST /company-management/sell-company',
    'POST /company-management/update-pricing',
    'POST /company-management/order-stock',
    'POST /company-management/update-advertising',
    'POST /company-management/buy-upgrade',
    'POST /credit-broker/purchase',
    'POST /info-broker/bounty',
    'POST /jail/bail',
    'POST /jail/breakout',
    'POST /jail/gym/train',
    'POST /jobs/exchange',
    'POST /premium/consume-pack',
    'POST /premium/subscribe',
    'POST /real-estate/buy-agency',
    'POST /real-estate/upgrade',
    'POST /real-estate/market/list-sale',
    'POST /real-estate/market/buy',
    'POST /real-estate/market/cancel',
    'POST /real-estate/lease',
    'POST /real-estate/give',
    'POST /real-estate/upkeep/pay',
    'POST /syndicate/assign_company',
    'POST /syndicate/complete_job',
    'POST /trade-network/list',
    'POST /trade-network/buy',
    'POST /trade-network/cancel'
]);

const MUTATION_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

function mutationContract(req, res, next) {
    if (!MUTATION_METHODS.has(req.method)) return next();

    const key = req.method + ' ' + req.path;

    // Paused routes are allowed to reach their explicit 410/503 handler. They
    // cannot mutate state, so accepting their legacy body shape does not create
    // an authority boundary.
    if (KNOWN_PAUSED_MUTATIONS.has(key)) return next();

    const allowedFields = ACTIVE_MUTATION_FIELDS.get(key);
    if (!allowedFields) {
        logger.warn('mutation_contract_missing', {
            request_id: req.requestId,
            method: req.method,
            path: req.path
        });
        return res.status(404).json({
            error: 'Mutation route is not registered.'
        });
    }

    if (req.query && Object.keys(req.query).length > 0) {
        logger.warn('mutation_contract_rejected_query', {
            request_id: req.requestId,
            method: req.method,
            path: req.path,
            query_field_count: Object.keys(req.query).length
        });
        return res.status(400).json({
            error: 'Mutation routes do not accept query parameters.'
        });
    }

    const body = req.body == null ? {} : req.body;
    if (typeof body !== 'object' || Array.isArray(body)) {
        logger.warn('mutation_contract_invalid_body', {
            request_id: req.requestId,
            method: req.method,
            path: req.path
        });
        return res.status(400).json({
            error: 'Mutation body must be a JSON object.'
        });
    }

    const allowed = new Set(allowedFields);
    const unknownFields = Object.keys(body).filter(field => !allowed.has(field));
    if (unknownFields.length > 0) {
        logger.warn('mutation_contract_rejected_fields', {
            request_id: req.requestId,
            method: req.method,
            path: req.path,
            rejected_field_count: unknownFields.length
        });
        return res.status(400).json({
            error: 'Unexpected request fields.'
        });
    }

    return next();
}

module.exports = {
    mutationContract,
    ACTIVE_MUTATION_FIELDS,
    KNOWN_PAUSED_MUTATIONS
};
