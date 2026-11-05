const express = require('express');
const router = express.Router();
// Reject URLs referencing any player other than the verified session owner.
const { requireOwnedPlayerParam } = require('../middleware/playerIdentity');
router.param('user_id', requireOwnedPlayerParam);

const pool = require('../db');
const { randomInt } = require('node:crypto');
const {
    ActionError, integer, dbInteger, exactJsonAmount, actorId, sendActionError
} = require('../utils/economyValidation');
const { requireIdempotencyKey, beginIdempotent, completeIdempotent } = require('../utils/idempotency');
const { handleCrewDomainTransfer } = require('../utils/crewDomain');
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
const RECRUITMENT_COOLDOWN_SECONDS = 120;

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
        return res.json({
            success: true,
            assignment_available: false,
            automation_status: 'paused_source_conflict',
            conflict:
                'Recruits Canvas specifies fixed 60-second loops and flat 1% mortality, while crimes_master carries per-crime automation/casualty values.',
            crimes
        });
    } catch (err) {
        return sendActionError(res, err, 'Crew crime board failed:');
    }
});

// --- ASSIGN CREW TO A CRIME ---
router.post('/assign_job', (_req, res) => {
    return res.status(503).json({
        error:
            'Crew crime assignment is paused until Recruits Canvas and crimes_master automation timing/mortality rules are reconciled.'
    });
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

router.post('/generate_board', (_req, res) => {
    return res.status(503).json({
        error:
            'Recruit generation is paused: Recruits Canvas stat ranges conflict with legacy generator ranges and the cost multipliers are not defined.'
    });
});

router.post('/hire', (_req, res) => {
    return res.status(503).json({
        error:
            'Recruit hiring is paused until recruit stat generation and purchase pricing are selected from an authoritative rule set.'
    });
});

router.post('/complete_job', (_req, res) => {
    // Crew crime settlement is server-scheduled. A client-triggered completion
    // endpoint would let callers race or fabricate settlement timing.
    return res.status(410).json({
        error: 'Crew crime payouts are settled automatically by the server.'
    });
});

module.exports = router;
