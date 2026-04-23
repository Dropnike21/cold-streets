const express = require('express');
const router = express.Router();
const pool = require('../db');

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

const getRnd = (min, max) => Math.floor(Math.random() * (max - min + 1)) + min;

async function generateUniqueName(userId) {
    let isUnique = false;
    let newName = "";
    while (!isUnique) {
        newName = `${firstNames[getRnd(0, firstNames.length - 1)]} ${lastNames[getRnd(0, lastNames.length - 1)]}`;
        const check = await pool.query('SELECT 1 FROM user_crew WHERE user_id = $1 AND npc_name = $2', [userId, newName]);
        if (check.rows.length === 0) isUnique = true;
    }
    return newName;
}

// --- ROUTES ---

// FETCH ACTIVE CREW & OWNED TOOLS
router.get('/:user_id', async (req, res) => {
    try {
        const { user_id } = req.params;

        const userRes = await pool.query('SELECT recruit_refreshes FROM users WHERE user_id = $1', [user_id]);
        const refreshesLeft = userRes.rows.length > 0 ? userRes.rows[0].recruit_refreshes : 0;

        const crewQuery = `
            SELECT uc.*, cm.tool_req
            FROM user_crew uc
            LEFT JOIN crimes_master cm ON uc.assignment = cm.title
            WHERE uc.user_id = $1
            ORDER BY (uc.max_str + uc.max_def + uc.max_dex + uc.max_spd + uc.max_acu + uc.max_ops + uc.max_pre + uc.max_res) DESC
        `;
        const crew = await pool.query(crewQuery, [user_id]);

        const toolsQuery = `
            SELECT UPPER(im.name) as name
            FROM user_inventory ui
            JOIN items_master im ON ui.item_id = im.item_id
            WHERE ui.user_id = $1 AND ui.quantity > 0
        `;
        const tools = await pool.query(toolsQuery, [user_id]);
        const ownedTools = tools.rows.map(t => t.name);

        res.json({ success: true, crew: crew.rows, refreshesLeft, ownedTools });
    } catch (err) {
        console.error("GET Crew Error:", err);
        res.status(500).json({ error: "Server error" });
    }
});

router.get('/crimes_board/:user_id', async (req, res) => {
    try {
        const crimes = await pool.query('SELECT * FROM crimes_master ORDER BY category ASC, req_stat_value ASC');
        res.json({ success: true, crimes: crimes.rows });
    } catch (err) {
        res.status(500).json({ error: "Server error" });
    }
});

router.post('/assign_job', async (req, res) => {
    const client = await pool.connect();
    try {
        const { user_id, crew_id, crime_title } = req.body;
        await client.query('BEGIN');

        await client.query("UPDATE user_crew SET assignment = 'UNASSIGNED' WHERE user_id = $1 AND assignment = $2", [user_id, crime_title]);
        await client.query("UPDATE user_crew SET assignment = $1 WHERE user_id = $2 AND crew_id = $3", [crime_title, user_id, crew_id]);

        await client.query('COMMIT');
        res.json({ success: true, message: `Assigned to ${crime_title}.` });
    } catch (err) {
        await client.query('ROLLBACK');
        res.status(500).json({ error: "Server error assigning job." });
    } finally {
        client.release();
    }
});

router.post('/unassign_job', async (req, res) => {
    try {
        const { user_id, crew_id } = req.body;
        await pool.query("UPDATE user_crew SET assignment = 'UNASSIGNED' WHERE user_id = $1 AND crew_id = $2", [user_id, crew_id]);
        res.json({ success: true, message: "Crew member recalled." });
    } catch (err) {
        res.status(500).json({ error: "Server error" });
    }
});

router.post('/generate_board', async (req, res) => {
    const client = await pool.connect();
    try {
        const { user_id } = req.body;

        await client.query('BEGIN');

        // V1.2 FIX: Cooldown Check! If active, board refuses to generate.
        const cdCheck = await client.query("SELECT EXTRACT(EPOCH FROM (expires_at - NOW())) AS seconds_left FROM user_cooldowns WHERE user_id = $1 AND type = 'recruitment' AND expires_at > NOW()", [user_id]);
        if (cdCheck.rows.length > 0) {
            await client.query('ROLLBACK');
            return res.status(403).json({
                error: "Scouts are on cooldown.",
                seconds_left: cdCheck.rows[0].seconds_left
            });
        }

        const userRes = await client.query('SELECT level, recruit_refreshes FROM users WHERE user_id = $1 FOR UPDATE', [user_id]);
        if (userRes.rows.length === 0) throw new Error("User not found");

        let { level, recruit_refreshes } = userRes.rows[0];

        if (recruit_refreshes <= 0) {
            await client.query('ROLLBACK');
            return res.status(403).json({ error: "No refreshes remaining today." });
        }

        await client.query('UPDATE users SET recruit_refreshes = recruit_refreshes - 1 WHERE user_id = $1', [user_id]);
        const refreshesLeft = recruit_refreshes - 1;

        let board = [];
        for (let i = 0; i < 5; i++) {
            let selectedTier = 1;
            const roll = getRnd(1, 100);

            if (level >= 50 && roll >= 99) selectedTier = 5;
            else if (level >= 35 && roll >= 90) selectedTier = 4;
            else if (level >= 25 && roll >= 70) selectedTier = 3;
            else if (level >= 15 && roll >= 40) selectedTier = 2;
            else selectedTier = 1;

            const tierMeta = TIER_DATA[selectedTier];
            const name = await generateUniqueName(user_id);

            const stats = {
                str: { cur: getRnd(tierMeta.curRange[0], tierMeta.curRange[1]), max: getRnd(tierMeta.maxRange[0], tierMeta.maxRange[1]) },
                def: { cur: getRnd(tierMeta.curRange[0], tierMeta.curRange[1]), max: getRnd(tierMeta.maxRange[0], tierMeta.maxRange[1]) },
                dex: { cur: getRnd(tierMeta.curRange[0], tierMeta.curRange[1]), max: getRnd(tierMeta.maxRange[0], tierMeta.maxRange[1]) },
                spd: { cur: getRnd(tierMeta.curRange[0], tierMeta.curRange[1]), max: getRnd(tierMeta.maxRange[0], tierMeta.maxRange[1]) },
                acu: { cur: getRnd(tierMeta.curRange[0], tierMeta.curRange[1]), max: getRnd(tierMeta.maxRange[0], tierMeta.maxRange[1]) },
                ops: { cur: getRnd(tierMeta.curRange[0], tierMeta.curRange[1]), max: getRnd(tierMeta.maxRange[0], tierMeta.maxRange[1]) },
                pre: { cur: getRnd(tierMeta.curRange[0], tierMeta.curRange[1]), max: getRnd(tierMeta.maxRange[0], tierMeta.maxRange[1]) },
                res: { cur: getRnd(tierMeta.curRange[0], tierMeta.curRange[1]), max: getRnd(tierMeta.maxRange[0], tierMeta.maxRange[1]) }
            };

            const totalCur = stats.str.cur + stats.def.cur + stats.dex.cur + stats.spd.cur + stats.acu.cur + stats.ops.cur + stats.pre.cur + stats.res.cur;

            // V1.2 FIX: Price Multiplier adjusted to reflect the massive stat boosts
            const price = (totalCur * 50) * selectedTier;

            board.push({ name, tier: tierMeta.name, barMax: tierMeta.barMax, stats, price });
        }

        await client.query('COMMIT');
        res.json({ success: true, board, refreshesLeft });
    } catch (err) {
        await client.query('ROLLBACK');
        res.status(500).json({ error: err.message || "Server error" });
    } finally {
        client.release();
    }
});

router.post('/hire', async (req, res) => {
    const client = await pool.connect();
    try {
        const { user_id, recruit } = req.body;

        await client.query('BEGIN');

        // Verify they aren't already on a cooldown
        const cdCheck = await client.query("SELECT * FROM user_cooldowns WHERE user_id = $1 AND type = 'recruitment' AND expires_at > NOW()", [user_id]);
        if (cdCheck.rows.length > 0) {
            throw new Error("Scouts are on cooldown.");
        }

        const userCheck = await client.query('SELECT dirty_cash FROM users WHERE user_id = $1 FOR UPDATE', [user_id]);
        if (userCheck.rows[0].dirty_cash < recruit.price) {
            throw new Error("Insufficient dirty cash.");
        }

        await client.query('UPDATE users SET dirty_cash = dirty_cash - $1 WHERE user_id = $2', [recruit.price, user_id]);

        await client.query(`
            INSERT INTO user_crew (
                user_id, npc_name, tier,
                cur_str, max_str, cur_def, max_def, cur_dex, max_dex, cur_spd, max_spd,
                cur_acu, max_acu, cur_ops, max_ops, cur_pre, max_pre, cur_res, max_res
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19)
        `, [
            user_id, recruit.name, recruit.tier,
            recruit.stats.str.cur, recruit.stats.str.max,
            recruit.stats.def.cur, recruit.stats.def.max,
            recruit.stats.dex.cur, recruit.stats.dex.max,
            recruit.stats.spd.cur, recruit.stats.spd.max,
            recruit.stats.acu.cur, recruit.stats.acu.max,
            recruit.stats.ops.cur, recruit.stats.ops.max,
            recruit.stats.pre.cur, recruit.stats.pre.max,
            recruit.stats.res.cur, recruit.stats.res.max
        ]);

        // V1.2 FIX: Inject the 2-Minute Cooldown immediately after hiring
        await client.query("INSERT INTO user_cooldowns (user_id, type, expires_at, reason) VALUES ($1, 'recruitment', NOW() + INTERVAL '2 minutes', 'Your scouts are out looking for new prospects.')", [user_id]);

        await client.query('COMMIT');
        res.json({ success: true, message: `${recruit.name} joined the crew.` });
    } catch (err) {
        await client.query('ROLLBACK');
        res.status(400).json({ error: err.message || "Server error" });
    } finally {
        client.release();
    }
});

router.post('/complete_job', async (req, res) => {
    const client = await pool.connect();
    try {
        const { user_id, crew_id, payout } = req.body;

        await client.query('BEGIN');

        const crewCheck = await client.query('SELECT * FROM user_crew WHERE crew_id = $1 AND user_id = $2 FOR UPDATE', [crew_id, user_id]);
        if (crewCheck.rows.length === 0) {
            throw new Error("Crew member not found or recalled.");
        }
        const crew = crewCheck.rows[0];

        const crimeData = await client.query('SELECT tool_req FROM crimes_master WHERE title = $1', [crew.assignment]);
        if (crimeData.rows.length > 0) {
            const toolReq = crimeData.rows[0].tool_req;
            if (toolReq && toolReq !== 'NONE') {
                const invCheck = await client.query(`
                    SELECT 1 FROM user_inventory ui
                    JOIN items_master im ON ui.item_id = im.item_id
                    WHERE ui.user_id = $1 AND UPPER(im.name) = UPPER($2) AND ui.quantity > 0
                `, [user_id, toolReq]);

                if (invCheck.rows.length === 0) {
                    throw new Error(`Job Failed. Missing required tool: ${toolReq}`);
                }
            }
        }

        const riskRoll = getRnd(1, 100);
        if (riskRoll === 1) {
            const disasterReasons = [
                "was hospitalized during a brutal ambush and had to leave the life behind.",
                "got caught by a federal sting. They are locked up for good.",
                "got spooked by the heat, took their cut, and vanished from the city."
            ];
            const reason = disasterReasons[getRnd(0, disasterReasons.length - 1)];

            await client.query('DELETE FROM user_crew WHERE crew_id = $1', [crew_id]);
            await client.query('COMMIT');

            return res.json({
                success: true,
                status: 'lost',
                message: `${crew.npc_name.toUpperCase()} ${reason}`
            });
        }

        await client.query('UPDATE users SET dirty_cash = dirty_cash + $1 WHERE user_id = $2', [payout, user_id]);

        let statGains = { str: 0, def: 0, dex: 0, spd: 0, acu: 0, ops: 0, pre: 0, res: 0 };
        const allStats = ['str', 'def', 'dex', 'spd', 'acu', 'ops', 'pre', 'res'];
        const shuffledStats = allStats.sort(() => 0.5 - Math.random());

        statGains[shuffledStats[0]] = 1;
        statGains[shuffledStats[1]] = 1;

        const updateQuery = `
            UPDATE user_crew
            SET cur_str = LEAST(cur_str + $1, max_str), cur_def = LEAST(cur_def + $2, max_def),
                cur_dex = LEAST(cur_dex + $3, max_dex), cur_spd = LEAST(cur_spd + $4, max_spd),
                cur_acu = LEAST(cur_acu + $5, max_acu), cur_ops = LEAST(cur_ops + $6, max_ops),
                cur_pre = LEAST(cur_pre + $7, max_pre), cur_res = LEAST(cur_res + $8, max_res)
            WHERE crew_id = $9 AND user_id = $10
            RETURNING cur_str, cur_def, cur_dex, cur_spd, cur_acu, cur_ops, cur_pre, cur_res
        `;
        const updatedCrew = await client.query(updateQuery, [
            statGains.str, statGains.def, statGains.dex, statGains.spd,
            statGains.acu, statGains.ops, statGains.pre, statGains.res,
            crew_id, user_id
        ]);

        await client.query('COMMIT');
        res.json({
            success: true,
            status: 'success',
            message: `${crew.npc_name} finished the job and returned $${payout}.`,
            newStats: updatedCrew.rows[0]
        });

    } catch (err) {
        await client.query('ROLLBACK');
        console.error("Job Completion Error:", err);
        res.status(400).json({ error: err.message || "Failed to process job completion." });
    } finally {
        client.release();
    }
});

module.exports = router;