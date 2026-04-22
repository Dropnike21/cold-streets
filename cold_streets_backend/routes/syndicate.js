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

const TIER_DATA = {
    1: { name: "Runner", minLvl: 1, curRange: [5, 25], maxRange: [40, 95], barMax: 100 },
    2: { name: "Hustler", minLvl: 15, curRange: [15, 40], maxRange: [70, 120], barMax: 150 },
    3: { name: "Enforcer", minLvl: 25, curRange: [25, 60], maxRange: [100, 160], barMax: 200 },
    4: { name: "Specialist", minLvl: 35, curRange: [30, 80], maxRange: [120, 180], barMax: 200 },
    5: { name: "Lieutenant", minLvl: 50, curRange: [50, 100], maxRange: [180, 250], barMax: 250 }
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

async function checkAndResetRefreshes(user_id) {
    const now = new Date();
    let reset = new Date();
    reset.setUTCHours(22, 0, 0, 0);

    if (now.getTime() < reset.getTime()) {
        reset.setUTCDate(reset.getUTCDate() - 1);
    }

    const userRes = await pool.query('SELECT recruit_refreshes, last_refresh_reset FROM users WHERE user_id = $1', [user_id]);
    if (userRes.rows.length === 0) return 0;

    let { recruit_refreshes, last_refresh_reset } = userRes.rows[0];

    if (!last_refresh_reset || new Date(last_refresh_reset).getTime() < reset.getTime()) {
        await pool.query('UPDATE users SET recruit_refreshes = 5, last_refresh_reset = NOW() WHERE user_id = $1', [user_id]);
        return 5;
    }

    return recruit_refreshes;
}

// --- ROUTES ---

// FETCH ACTIVE CREW & OWNED TOOLS
router.get('/:user_id', async (req, res) => {
    try {
        const { user_id } = req.params;
        await checkAndResetRefreshes(user_id);

        // 1. Fetch Crew & ATTACH the Tool Requirement for their current assignment
        const crewQuery = `
            SELECT uc.*, cm.tool_req
            FROM user_crew uc
            LEFT JOIN crimes_master cm ON uc.assignment = cm.title
            WHERE uc.user_id = $1
            ORDER BY uc.max_str + uc.max_def + uc.max_dex + uc.max_spd + uc.max_int DESC
        `;
        const crew = await pool.query(crewQuery, [user_id]);

        // 2. Fetch exactly what tools the player owns (> 0)
        const toolsQuery = `
            SELECT UPPER(im.name) as name
            FROM user_inventory ui
            JOIN items_master im ON ui.item_id = im.item_id
            WHERE ui.user_id = $1 AND ui.quantity > 0
        `;
        const tools = await pool.query(toolsQuery, [user_id]);
        const ownedTools = tools.rows.map(t => t.name);

        res.json({ success: true, crew: crew.rows, refreshesLeft: 99, ownedTools });
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
    try {
        const { user_id, crew_id, crime_title } = req.body;
        await pool.query('BEGIN');
        await pool.query("UPDATE user_crew SET assignment = 'UNASSIGNED' WHERE user_id = $1 AND assignment = $2", [user_id, crime_title]);
        await pool.query("UPDATE user_crew SET assignment = $1 WHERE user_id = $2 AND crew_id = $3", [crime_title, user_id, crew_id]);
        await pool.query('COMMIT');
        res.json({ success: true, message: `Assigned to ${crime_title}.` });
    } catch (err) {
        await pool.query('ROLLBACK');
        res.status(500).json({ error: "Server error" });
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
    try {
        const { user_id } = req.body;
        const userRes = await pool.query('SELECT level FROM users WHERE user_id = $1', [user_id]);
        if (userRes.rows.length === 0) return res.status(404).json({ error: "User not found" });
        let { level } = userRes.rows[0];

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
                int: { cur: getRnd(tierMeta.curRange[0], tierMeta.curRange[1]), max: getRnd(tierMeta.maxRange[0], tierMeta.maxRange[1]) }
            };

            const totalCur = stats.str.cur + stats.def.cur + stats.dex.cur + stats.spd.cur + stats.int.cur;
            const price = (totalCur * 10) * selectedTier;

            board.push({ name, tier: tierMeta.name, barMax: tierMeta.barMax, stats, price });
        }

        res.json({ success: true, board, refreshesLeft: 99 });
    } catch (err) {
        res.status(500).json({ error: "Server error" });
    }
});

router.post('/hire', async (req, res) => {
    try {
        const { user_id, recruit } = req.body;
        const userCheck = await pool.query('SELECT dirty_cash FROM users WHERE user_id = $1', [user_id]);
        if (userCheck.rows[0].dirty_cash < recruit.price) {
            return res.status(400).json({ error: "Insufficient dirty cash." });
        }

        await pool.query('UPDATE users SET dirty_cash = dirty_cash - $1 WHERE user_id = $2', [recruit.price, user_id]);
        await pool.query(`
            INSERT INTO user_crew (user_id, npc_name, tier, cur_str, max_str, cur_def, max_def, cur_dex, max_dex, cur_spd, max_spd, cur_int, max_int)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
        `, [
            user_id, recruit.name, recruit.tier,
            recruit.stats.str.cur, recruit.stats.str.max,
            recruit.stats.def.cur, recruit.stats.def.max,
            recruit.stats.dex.cur, recruit.stats.dex.max,
            recruit.stats.spd.cur, recruit.stats.spd.max,
            recruit.stats.int.cur, recruit.stats.int.max
        ]);

        res.json({ success: true, message: `${recruit.name} joined the crew.` });
    } catch (err) {
        res.status(500).json({ error: "Server error" });
    }
});

// POST: Complete Automated Crew Job & Process Stat Growth (WITH 1% RISK & +1 STAT GAIN)
router.post('/complete_job', async (req, res) => {
    try {
        const { user_id, crew_id, crime_category, payout } = req.body;
        await pool.query('BEGIN');

        // 1. Check if they exist and haven't been recalled
        const crewCheck = await pool.query('SELECT * FROM user_crew WHERE crew_id = $1 AND user_id = $2', [crew_id, user_id]);
        if (crewCheck.rows.length === 0) {
            await pool.query('ROLLBACK');
            return res.status(400).json({ error: "Crew member not found or recalled." });
        }
        const crew = crewCheck.rows[0];

        // 2. Tool Requirement Check
        const crimeData = await pool.query('SELECT tool_req FROM crimes_master WHERE title = $1', [crew.assignment]);
        if (crimeData.rows.length > 0) {
            const toolReq = crimeData.rows[0].tool_req;
            if (toolReq && toolReq !== 'NONE') {
                const invCheck = await pool.query(`
                    SELECT 1 FROM user_inventory ui
                    JOIN items_master im ON ui.item_id = im.item_id
                    WHERE ui.user_id = $1 AND UPPER(im.name) = UPPER($2) AND ui.quantity > 0
                `, [user_id, toolReq]);

                if (invCheck.rows.length === 0) {
                    await pool.query('ROLLBACK');
                    return res.status(400).json({ error: `Job Failed. Missing required tool: ${toolReq}` });
                }
            }
        }

        // ==========================================
        // THE 1% PERMADEATH / ABANDONMENT ROLL
        // ==========================================
        const riskRoll = getRnd(1, 100);
        if (riskRoll === 1) { // 1% Chance of disaster
            const disasterReasons = [
                "was hospitalized during a brutal ambush and had to leave the life behind.",
                "got caught by a federal sting. They are locked up for good.",
                "got spooked by the heat, took their cut, and vanished from the city."
            ];
            const reason = disasterReasons[getRnd(0, disasterReasons.length - 1)];

            // Delete the crew member permanently
            await pool.query('DELETE FROM user_crew WHERE crew_id = $1', [crew_id]);
            await pool.query('COMMIT');

            return res.json({
                success: true,
                status: 'lost',
                message: `${crew.npc_name.toUpperCase()} ${reason}`
            });
        }
        // ==========================================

        // 3. Give Player Cash (If they survived)
        await pool.query('UPDATE users SET dirty_cash = dirty_cash + $1 WHERE user_id = $2', [payout, user_id]);

        // ==========================================
        // 4. THE NEW STAT GROWTH (+1 to 2 random stats)
        // ==========================================
        let strGain = 0, defGain = 0, dexGain = 0, spdGain = 0, intGain = 0;

        // Array of the 5 core stats
        const allStats = ['str', 'def', 'dex', 'spd', 'int'];

        // Shuffle the array to pick 2 unique random stats
        const shuffledStats = allStats.sort(() => 0.5 - Math.random());
        const stat1 = shuffledStats[0];
        const stat2 = shuffledStats[1];

        // Apply +1 to whichever two stats won the shuffle
        if (stat1 === 'str' || stat2 === 'str') strGain = 1;
        if (stat1 === 'def' || stat2 === 'def') defGain = 1;
        if (stat1 === 'dex' || stat2 === 'dex') dexGain = 1;
        if (stat1 === 'spd' || stat2 === 'spd') spdGain = 1;
        if (stat1 === 'int' || stat2 === 'int') intGain = 1;

        // Safely Update Stats (Capped at Maximum Potential)
        const updateQuery = `
            UPDATE user_crew
            SET cur_str = LEAST(cur_str + $1, max_str), cur_def = LEAST(cur_def + $2, max_def),
                cur_dex = LEAST(cur_dex + $3, max_dex), cur_spd = LEAST(cur_spd + $4, max_spd),
                cur_int = LEAST(cur_int + $5, max_int)
            WHERE crew_id = $6 AND user_id = $7 RETURNING cur_str, cur_def, cur_dex, cur_spd, cur_int
        `;
        const updatedCrew = await pool.query(updateQuery, [strGain, defGain, dexGain, spdGain, intGain, crew_id, user_id]);

        await pool.query('COMMIT');
        res.json({
            success: true,
            status: 'success',
            message: `${crew.npc_name} finished the job and returned $${payout}.`,
            newStats: updatedCrew.rows[0]
        });
    } catch (err) {
        await pool.query('ROLLBACK');
        console.error("Job Completion Error:", err);
        res.status(500).json({ error: "Failed to process job completion." });
    }
});

module.exports = router;