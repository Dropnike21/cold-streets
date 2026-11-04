const express = require('express');
const router = express.Router();
// Reject URLs referencing any player other than the verified session owner.
const { requireOwnedPlayerParam } = require('../middleware/playerIdentity');
router.param('user_id', requireOwnedPlayerParam);

const pool = require('../db');
const { randomInt } = require('node:crypto');
const { ActionError, integer, dbInteger, actorId, sendActionError } = require('../utils/economyValidation');
const { requireIdempotencyKey, beginIdempotent, completeIdempotent } = require('../utils/idempotency');
const {
    getCrewCrimeRule, listCrewCrimeRules, ownsRequiredTool
} = require('../utils/crewCrimeCatalog');

// --- CONSTANTS & POOLS ---
const firstNames = [
    "Aaron", "Adrian", "Alejandro", "Alex", "Alonzo", "Andre", "Andres", "Anthony", "Antonio", "Armando",
    "Arthur", "Benjamin", "Brian", "Caleb", "Calvin", "Camila", "Carlos", "Carmen", "Carter", "Cesar",
    "Charles", "Christian", "Christopher", "Claudia", "Damian", "Daniel", "Dante", "Darius", "David", "Desmond",
    "Diego", "Dominic", "Edgar", "Eduardo", "Elena", "Elias", "Emilio", "Emmanuel", "Eric", "Esteban",
    "Eva", "Fernando", "Francisco", "Gabriel", "Hector", "Hugo", "Isaac", "Isabella", "Ivan", "Jace",
    "Jackson", "Jacob", "Jamal", "James", "Javier", "Jax", "Jeremiah", "Jesse", "Jimmy", "Joaquin",
    "John", "Jonathan", "Jordan", "Jorge", "Jose", "Joseph", "Juan", "Julian", "Julio", "Justin",
    "Kevin", "Leo", "Leon", "Leonardo", "Lorenzo", "Lucas", "Luis", "Malik", "Manuel", "Marcus",
    "Maria", "Mario", "Martin", "Mateo", "Matthew", "Mia", "Michael", "Miguel", "Miles", "Nathaniel",
    "Nicolas", "Oscar", "Pablo", "Pedro", "Rafael", "Ramon", "Raul", "Raymond", "Ricardo", "Richard",
    "Robert", "Roberto", "Roman", "Rosa", "Ruben", "Ryan", "Samuel", "Santiago", "Silas", "Sofia",
    "Thomas", "Tommy", "Tyler", "Tyrone", "Valentina", "Victor", "Vincent", "William", "Xavier", "Zachary"
];

const lastNames = [
    "Aguilar", "Alvarez", "Arias", "Avila", "Ayala", "Bautista", "Beltran", "Benitez", "Black", "Brooks",
    "Cabrera", "Calderon", "Camacho", "Campos", "Cardenas", "Carrillo", "Castaneda", "Castillo", "Castro", "Cervantes",
    "Chavez", "Cisneros", "Contreras", "Cordova", "Corona", "Coronado", "Cortez", "Cross", "Cruz", "Daniels",
    "Delgado", "Diaz", "Dominguez", "Duran", "Escobar", "Espinoza", "Estrada", "Fernandez", "Figueroa", "Flores",
    "Franco", "Fuentes", "Gallardo", "Galvan", "Garcia", "Garza", "Gomez", "Gonzales", "Gonzalez", "Guerra",
    "Guerrero", "Gutierrez", "Guzman", "Hernandez", "Herrera", "Huerta", "Jackson", "Jenkins", "Jimenez", "Juarez",
    "Lara", "Leon", "Lopez", "Lozano", "Luna", "Macias", "Marquez", "Martinez", "Medina", "Mejia",
    "Melendez", "Mendez", "Mendoza", "Mercado", "Miranda", "Molina", "Montes", "Montoya", "Mora", "Morales",
    "Moreno", "Munoz", "Navarro", "Nelson", "Nunez", "Ochoa", "Orozco", "Ortiz", "Pacheco", "Padilla",
    "Palacios", "Pena", "Perez", "Pineda", "Ponce", "Price", "Ramirez", "Ramos", "Reed", "Reyes",
    "Rios", "Rivas", "Rivera", "Robles", "Rocha", "Rodriguez", "Rojas", "Roman", "Romero", "Rosales",
    "Ruiz", "Salas", "Salazar", "Salinas", "Sanchez", "Sandoval", "Santana", "Santiago", "Santos", "Serrano",
    "Silva", "Solis", "Soto", "Suarez", "Tapia", "Torres", "Trevino", "Trujillo", "Valdez", "Valenzuela"
];

// V1.2 FIX: Massive Stat Boost & Progression Scaling
const TIER_DATA = {
    1: { name: "Runner", minLvl: 1, curRange: [10, 50], maxRange: [100, 1000], barMax: 1000 },
    2: { name: "Hustler", minLvl: 15, curRange: [100, 500], maxRange: [2000, 10000], barMax: 10000 },
    3: { name: "Enforcer", minLvl: 25, curRange: [1000, 5000], maxRange: [20000, 80000], barMax: 80000 },
    4: { name: "Specialist", minLvl: 35, curRange: [10000, 25000], maxRange: [100000, 350000], barMax: 350000 },
    5: { name: "Lieutenant", minLvl: 50, curRange: [50000, 100000], maxRange: [500000, 1000000], barMax: 1000000 }
};

const getRnd = (min, max) => randomInt(min, max + 1);

async function generateUniqueName(client, userId, reserved = new Set()) {
    for (let attempts = 0; attempts < 100; attempts++) {
        const name = firstNames[getRnd(0, firstNames.length - 1)] + ' ' +
            lastNames[getRnd(0, lastNames.length - 1)];
        if (reserved.has(name)) continue;
        const check = await client.query(
            `SELECT 1
               FROM user_crew
              WHERE user_id = $1 AND npc_name = $2
             UNION ALL
             SELECT 1
               FROM recruitment_offers
              WHERE user_id = $1 AND npc_name = $2
                AND claimed_at IS NULL AND expires_at > NOW()
             LIMIT 1`,
            [userId, name]
        );
        if (!check.rowCount) {
            reserved.add(name);
            return name;
        }
    }
    throw new Error('Could not generate a unique recruit name.');
}

// --- ROUTES ---

// FETCH ACTIVE CREW & OWNED TOOLS
router.get('/:user_id', async (req, res) => {
    try {
        const { user_id } = req.params;

        const userRes = await pool.query(
            'SELECT recruit_refreshes FROM users WHERE user_id = $1',
            [user_id]
        );
        const refreshesLeft = userRes.rows.length > 0
            ? userRes.rows[0].recruit_refreshes
            : 0;

        const crew = await pool.query(
            `SELECT uc.*,
                    cca.crime_id,
                    cca.next_tick_at,
                    cca.last_tick_at,
                    cm.title AS scheduled_crime_title,
                    COALESCE(tool.name, 'NONE') AS tool_req,
                    tool.item_id AS tool_item_id
               FROM user_crew uc
               LEFT JOIN crew_crime_assignments cca
                 ON cca.crew_id = uc.crew_id
               LEFT JOIN crimes_master cm
                 ON cm.id = cca.crime_id
               LEFT JOIN items_master tool
                 ON tool.item_id::text = cm.requirements_json->>'tool_req'
              WHERE uc.user_id = $1
              ORDER BY (
                uc.max_str + uc.max_def + uc.max_dex + uc.max_spd +
                uc.max_acu + uc.max_ops + uc.max_pre + uc.max_res
              ) DESC`,
            [user_id]
        );
        const crewRows = crew.rows.map(row => ({
            ...row,
            assignment: row.scheduled_crime_title || 'UNASSIGNED'
        }));

        const tools = await pool.query(
            `SELECT UPPER(im.name) AS name
               FROM user_inventory ui
               JOIN items_master im ON ui.item_id = im.item_id
              WHERE ui.user_id = $1 AND ui.quantity > 0`,
            [user_id]
        );
        const ownedTools = tools.rows.map(t => t.name);

        return res.json({
            success: true,
            crew: crewRows,
            refreshesLeft,
            ownedTools
        });
    } catch (err) {
        return sendActionError(res, err, 'GET crew failed:');
    }
});

router.get('/crimes_board/:user_id', async (_req, res) => {
    try {
        const rules = await listCrewCrimeRules(pool);
        const crimes = rules.map(rule => ({
            id: rule.crimeId,
            category: rule.category,
            sub_category: rule.subCategory,
            title: rule.title,
            automation_seconds: rule.automationSeconds,
            min_payout: rule.minCash,
            max_payout: rule.maxCash,
            average_payout: rule.averageCash,
            casualty_ppm: rule.casualtyPpm,
            tool_item_id: rule.toolItemId,
            tool_req: rule.toolName
        }));
        return res.json({ success: true, crimes });
    } catch (err) {
        return sendActionError(res, err, 'Crew crime board failed:');
    }
});

// --- HELPER: CHECK DOMAIN TRANSFER ---
async function handleDomainTransfer(client, userId, crewId, newDomain) {
    const crewRes = await client.query(
        `SELECT current_domain,
                GREATEST(
                    0,
                    CEIL(EXTRACT(EPOCH FROM (
                        (last_transfer_at + INTERVAL '10 minutes') - NOW()
                    )))
                )::bigint AS transfer_seconds_remaining
           FROM user_crew
          WHERE crew_id = $1 AND user_id = $2
          FOR UPDATE`,
        [crewId, userId]
    );
    if (crewRes.rowCount !== 1) throw new ActionError(404, 'Crew member not found.');
    const crew = crewRes.rows[0];
    const currentDomain = crew.current_domain || 'IDLE';
    const remainingSeconds = crew.transfer_seconds_remaining == null
        ? 0
        : Number(crew.transfer_seconds_remaining);

    if (!Number.isSafeInteger(remainingSeconds) || remainingSeconds < 0) {
        throw new Error('Invalid crew transfer cooldown state.');
    }
    if (currentDomain !== 'IDLE' && currentDomain !== newDomain &&
        remainingSeconds > 0) {
        throw new ActionError(
            409,
            'Transfer cooldown active for ' +
                Math.ceil(remainingSeconds / 60) + ' more minute(s).'
        );
    }
    if (currentDomain !== newDomain) {
        await client.query(
            'UPDATE user_crew SET current_domain = $1, last_transfer_at = NOW() WHERE crew_id = $2 AND user_id = $3',
            [newDomain, crewId, userId]
        );
    }
}

// --- ASSIGN CREW TO A CRIME ---
router.post('/assign_job', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        const crewId = integer(req.body?.crew_id, {
            field: 'Crew ID', min: 1n, max: 9223372036854775807n
        }).toString();

        let crimeId = null;
        let crimeTitle = null;
        if (req.body?.crime_id !== undefined && req.body?.crime_id !== null) {
            crimeId = integer(req.body.crime_id, {
                field: 'Crime ID', min: 1n, max: 9223372036854775807n
            }).toString();
        } else if (typeof req.body?.crime_title === 'string' &&
                   req.body.crime_title.trim().length > 0 &&
                   req.body.crime_title.trim().length <= 200) {
            crimeTitle = req.body.crime_title.trim();
        } else {
            throw new ActionError(400, 'A catalog crime identifier is required.');
        }

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        // Match the worker lock order: schedule -> crew -> user -> inventory.
        await client.query(
            `SELECT crew_id
               FROM crew_crime_assignments
              WHERE crew_id = $1
              FOR UPDATE`,
            [crewId]
        );
        const crew = await client.query(
            `SELECT crew_id, current_domain, last_transfer_at
               FROM user_crew
              WHERE crew_id = $1 AND user_id = $2
              FOR UPDATE`,
            [crewId, userId]
        );
        if (crew.rowCount !== 1) {
            throw new ActionError(404, 'Crew member not found.');
        }
        const player = await client.query(
            'SELECT user_id FROM users WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (player.rowCount !== 1) throw new ActionError(404, 'Player not found.');

        const idem = await beginIdempotent(
            client,
            userId,
            'syndicate.assign_crew_crime',
            idempotencyKey,
            { crewId, crimeId, crimeTitle }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        const rule = await getCrewCrimeRule(
            client,
            crimeId !== null ? { crimeId } : { crimeTitle }
        );

        const hasTool = await ownsRequiredTool(
            client,
            userId,
            rule,
            { lock: true }
        );
        if (!hasTool) {
            throw new ActionError(
                409,
                'Required tool is not present in the player inventory.'
            );
        }

        await handleDomainTransfer(client, userId, crewId, 'CRIMES');

        const scheduled = await client.query(
            `INSERT INTO crew_crime_assignments (
                 crew_id, crime_id, assigned_at, next_tick_at, last_tick_at, updated_at
             )
             VALUES (
                 $1, $2::bigint, NOW(),
                 NOW() + ($3::bigint * INTERVAL '1 second'),
                 NULL, NOW()
             )
             ON CONFLICT (crew_id) DO UPDATE
                 SET crime_id = EXCLUDED.crime_id,
                     assigned_at = EXCLUDED.assigned_at,
                     next_tick_at = EXCLUDED.next_tick_at,
                     last_tick_at = NULL,
                     updated_at = NOW()
             RETURNING next_tick_at`,
            [crewId, rule.crimeId, rule.automationSeconds]
        );

        await client.query(
            `UPDATE user_crew
                SET assignment = $1,
                    current_domain = 'CRIMES'
              WHERE user_id = $2 AND crew_id = $3`,
            [rule.title, userId, crewId]
        );

        const response = {
            success: true,
            message: 'Crew crime automation scheduled.',
            crew_id: crewId,
            crime_id: rule.crimeId,
            crime_title: rule.title,
            average_payout: rule.averageCash,
            automation_seconds: rule.automationSeconds,
            casualty_ppm: rule.casualtyPpm,
            next_tick_at: scheduled.rows[0].next_tick_at
        };
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) {
                console.error('Crew assignment rollback:', rollback);
            }
        }
        return sendActionError(res, err, 'Crew assignment failed:');
    } finally {
        if (client) client.release();
    }
});

// Company NPC positions cannot be authorized safely until the canonical company
// position catalog is reconciled. Do not accept a client-supplied position role.
router.post('/assign_company', (_req, res) =>
    res.status(503).json({ error: 'Company crew assignment is paused pending company position catalog reconciliation.' })
);

router.post('/unassign_job', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        const crewId = integer(req.body?.crew_id, {
            field: 'Crew ID', min: 1n, max: 9223372036854775807n
        }).toString();

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        await client.query(
            `SELECT crew_id
               FROM crew_crime_assignments
              WHERE crew_id = $1
              FOR UPDATE`,
            [crewId]
        );
        const crew = await client.query(
            `SELECT crew_id
               FROM user_crew
              WHERE crew_id = $1 AND user_id = $2
              FOR UPDATE`,
            [crewId, userId]
        );
        if (crew.rowCount !== 1) {
            throw new ActionError(404, 'Crew member not found.');
        }
        const player = await client.query(
            'SELECT user_id FROM users WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (player.rowCount !== 1) throw new ActionError(404, 'Player not found.');

        const idem = await beginIdempotent(
            client,
            userId,
            'syndicate.unassign_crew_crime',
            idempotencyKey,
            { crewId }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        await client.query(
            'DELETE FROM crew_crime_assignments WHERE crew_id = $1',
            [crewId]
        );
        await client.query(
            `UPDATE user_crew
                SET assignment = 'UNASSIGNED',
                    current_domain = 'CRIMES'
              WHERE user_id = $1 AND crew_id = $2`,
            [userId, crewId]
        );

        const response = {
            success: true,
            message: 'Crew member recalled.',
            crew_id: crewId
        };
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); }
            catch (rollback) {
                console.error('Crew recall rollback:', rollback);
            }
        }
        return sendActionError(res, err, 'Crew recall failed:');
    } finally {
        if (client) client.release();
    }
});

router.post('/generate_board', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        const userRes = await client.query(
            'SELECT level, recruit_refreshes FROM users WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (userRes.rowCount !== 1) throw new ActionError(404, 'Player not found.');
        const idem = await beginIdempotent(
            client, userId, 'syndicate.generate_board', idempotencyKey, {}
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        const cdCheck = await client.query(
            `SELECT EXTRACT(EPOCH FROM (expires_at - NOW())) AS seconds_left
               FROM user_cooldowns
              WHERE user_id = $1 AND type = 'recruitment' AND expires_at > NOW()
              ORDER BY expires_at DESC LIMIT 1`,
            [userId]
        );
        if (cdCheck.rowCount) {
            throw new ActionError(409, 'Scouts are on cooldown.');
        }

        const level = Number(userRes.rows[0].level);
        const refreshes = Number(userRes.rows[0].recruit_refreshes);
        if (!Number.isSafeInteger(level) || level < 1) throw new Error('Invalid player level.');
        if (!Number.isSafeInteger(refreshes) || refreshes <= 0) {
            throw new ActionError(409, 'No recruitment refreshes remaining.');
        }

        await client.query(
            'UPDATE users SET recruit_refreshes = recruit_refreshes - 1 WHERE user_id = $1',
            [userId]
        );
        await client.query(
            'DELETE FROM recruitment_offers WHERE user_id = $1 AND claimed_at IS NULL',
            [userId]
        );

        const reserved = new Set();
        const board = [];
        for (let i = 0; i < 5; i++) {
            let tier = 1;
            const roll = getRnd(1, 100);
            if (level >= 50 && roll >= 99) tier = 5;
            else if (level >= 35 && roll >= 90) tier = 4;
            else if (level >= 25 && roll >= 70) tier = 3;
            else if (level >= 15 && roll >= 40) tier = 2;

            const meta = TIER_DATA[tier];
            const name = await generateUniqueName(client, userId, reserved);
            const stats = {};
            for (const stat of ['str','def','dex','spd','acu','ops','pre','res']) {
                stats[stat] = {
                    cur: getRnd(meta.curRange[0], meta.curRange[1]),
                    max: getRnd(meta.maxRange[0], meta.maxRange[1])
                };
            }
            const totalCur = Object.values(stats).reduce((sum, stat) => sum + stat.cur, 0);
            const price = BigInt(totalCur) * 50n * BigInt(tier);

            const inserted = await client.query(
                `INSERT INTO recruitment_offers (
                    user_id, npc_name, tier, price,
                    cur_str,max_str,cur_def,max_def,cur_dex,max_dex,cur_spd,max_spd,
                    cur_acu,max_acu,cur_ops,max_ops,cur_pre,max_pre,cur_res,max_res
                 ) VALUES (
                    $1,$2,$3,$4::numeric,
                    $5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20
                 )
                 RETURNING offer_id, expires_at`,
                [
                    userId,name,tier,price.toString(),
                    stats.str.cur,stats.str.max,stats.def.cur,stats.def.max,
                    stats.dex.cur,stats.dex.max,stats.spd.cur,stats.spd.max,
                    stats.acu.cur,stats.acu.max,stats.ops.cur,stats.ops.max,
                    stats.pre.cur,stats.pre.max,stats.res.cur,stats.res.max
                ]
            );
            board.push({
                offer_id: inserted.rows[0].offer_id,
                expires_at: inserted.rows[0].expires_at,
                name,
                tier: meta.name,
                tier_id: tier,
                barMax: meta.barMax,
                stats,
                price: Number(price)
            });
        }

        const response = {
            success: true,
            board,
            refreshesLeft: refreshes - 1
        };
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); } catch (rollback) { console.error('Recruit board rollback:', rollback); }
        }
        return sendActionError(res, err, 'Recruit board generation failed:');
    } finally { if (client) client.release(); }
});

router.post('/hire', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        const offerId = req.body?.offer_id;
        if (typeof offerId !== 'string' ||
            !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(offerId)) {
            throw new ActionError(400, 'Invalid recruitment offer.');
        }

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;
        const player = await client.query(
            'SELECT dirty_cash FROM users WHERE user_id = $1 FOR UPDATE', [userId]
        );
        if (player.rowCount !== 1) throw new ActionError(404, 'Player not found.');
        const idem = await beginIdempotent(
            client, userId, 'syndicate.hire', idempotencyKey, { offerId }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        const cooldown = await client.query(
            `SELECT 1 FROM user_cooldowns
              WHERE user_id = $1 AND type = 'recruitment' AND expires_at > NOW()
              LIMIT 1`,
            [userId]
        );
        if (cooldown.rowCount) throw new ActionError(409, 'Scouts are on cooldown.');

        const offerRes = await client.query(
            `SELECT *
               FROM recruitment_offers
              WHERE offer_id = $1::uuid AND user_id = $2
                AND claimed_at IS NULL AND expires_at > NOW()
              FOR UPDATE`,
            [offerId, userId]
        );
        if (offerRes.rowCount !== 1) {
            throw new ActionError(409, 'Recruitment offer expired or unavailable.');
        }
        const offer = offerRes.rows[0];
        const price = dbInteger(offer.price, { field: 'Recruit price' });
        if (dbInteger(player.rows[0].dirty_cash) < price) {
            throw new ActionError(409, 'Insufficient Dirty Cash.');
        }
        const debit = await client.query(
            'UPDATE users SET dirty_cash = dirty_cash - $1::numeric WHERE user_id = $2 AND dirty_cash >= $1::numeric RETURNING dirty_cash',
            [price.toString(), userId]
        );
        if (debit.rowCount !== 1) throw new ActionError(409, 'Wallet changed before recruitment.');

        const crew = await client.query(
            `INSERT INTO user_crew (
                user_id,npc_name,tier,
                cur_str,max_str,cur_def,max_def,cur_dex,max_dex,cur_spd,max_spd,
                cur_acu,max_acu,cur_ops,max_ops,cur_pre,max_pre,cur_res,max_res
             ) VALUES (
                $1,$2,$3,
                $4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19
             )
             RETURNING crew_id`,
            [
                userId,offer.npc_name,offer.tier,
                offer.cur_str,offer.max_str,offer.cur_def,offer.max_def,
                offer.cur_dex,offer.max_dex,offer.cur_spd,offer.max_spd,
                offer.cur_acu,offer.max_acu,offer.cur_ops,offer.max_ops,
                offer.cur_pre,offer.max_pre,offer.cur_res,offer.max_res
            ]
        );
        await client.query(
            'UPDATE recruitment_offers SET claimed_at = NOW() WHERE offer_id = $1::uuid AND user_id = $2',
            [offerId, userId]
        );
        await client.query(
            `INSERT INTO user_cooldowns (user_id,type,expires_at,reason)
             VALUES ($1,'recruitment',NOW() + INTERVAL '2 minutes',
                     'Your scouts are out looking for new prospects.')`,
            [userId]
        );

        const response = {
            success: true,
            message: offer.npc_name + ' joined the crew.',
            crew_id: crew.rows[0].crew_id,
            dirty_cash: debit.rows[0].dirty_cash
        };
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); } catch (rollback) { console.error('Recruit hire rollback:', rollback); }
        }
        return sendActionError(res, err, 'Recruit hire failed:');
    } finally { if (client) client.release(); }
});

router.post('/complete_job', (_req, res) => {
    // Crew crime settlement is server-scheduled. A client-triggered completion
    // endpoint would let callers race or fabricate settlement timing.
    return res.status(410).json({
        error: 'Crew crime payouts are settled automatically by the server.'
    });
});

module.exports = router;
