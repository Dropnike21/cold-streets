const express = require('express');
const router = express.Router();
const pool = require('../db');

// ==========================================
// STATIC SERVER AUTHORITY: JOB SPECIALS
// Maps job_id -> rank -> special data
// ==========================================
const JOB_SPECIALS = {
    1: { // City Hospital
        1: { name: "Scavenge", cost: 10, type: "item", item_id: 101, qty_per_exchange: 1 }, // 101 = Bandage
        2: { name: "First Aid", cost: 5, type: "heal", heal_amount: 15 },
        4: { name: "Pharmacy Access", cost: 25, type: "item", item_id: 102, qty_per_exchange: 1 }, // 102 = Morphine
        5: { name: "Revive", cost: 50, type: "revive" } // Complex logic for future update
    },
    // Future jobs can be mapped here (Job 2: Police, Job 3: Bank)
};

// --- 1. GET JOB DASHBOARD ---
router.get('/:user_id', async (req, res) => {
    try {
        const { user_id } = req.params;

        const userRes = await pool.query('SELECT current_job_id, daily_job_claimed_at FROM users WHERE user_id = $1', [user_id]);
        if (userRes.rows.length === 0) return res.status(404).json({ error: "User not found." });
        const user = userRes.rows[0];

        const jobsRes = await pool.query('SELECT * FROM jobs_master ORDER BY job_id ASC');
        const jobDataRes = await pool.query('SELECT * FROM user_job_data WHERE user_id = $1', [user_id]);
        const userJobs = jobDataRes.rows;

        const mappedJobs = jobsRes.rows.map(job => {
            const uData = userJobs.find(uj => uj.job_id === job.job_id);
            return {
                job_id: job.job_id,
                job_name: job.job_name,
                primary_stat: job.primary_stat,
                mastery_passive: job.mastery_passive_desc,
                mastery_active: job.mastery_active_desc,
                is_current: user.current_job_id === job.job_id,
                current_rank: uData ? uData.current_rank : 1,
                incentive_balance: uData ? uData.incentive_balance : 0,
                is_mastered: uData ? uData.is_mastered : false,
                ban_expiry: uData ? uData.ban_expiry : null
            };
        });

        res.json({
            success: true,
            current_job_id: user.current_job_id,
            last_claimed: user.daily_job_claimed_at,
            jobs: mappedJobs
        });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: "Server error fetching jobs dashboard." });
    }
});

// --- 2. GET INTERVIEW QUESTIONS ---
router.get('/interview/:job_id/:user_id', async (req, res) => {
    try {
        const { job_id, user_id } = req.params;

        const banCheck = await pool.query('SELECT ban_expiry FROM user_job_data WHERE user_id = $1 AND job_id = $2', [user_id, job_id]);
        if (banCheck.rows.length > 0 && banCheck.rows[0].ban_expiry) {
            const banExpiry = new Date(banCheck.rows[0].ban_expiry);
            if (banExpiry > new Date()) {
                return res.status(403).json({ error: "You recently failed an interview here. Try again later.", ban_expiry: banExpiry });
            }
        }

        const qRes = await pool.query(`
            SELECT question_id, question_text, options
            FROM job_interviews
            WHERE job_id = $1
            ORDER BY RANDOM() LIMIT 5
        `, [job_id]);

        if (qRes.rows.length < 5) return res.status(400).json({ error: "Not enough questions in the database for this job." });

        res.json({ success: true, questions: qRes.rows });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: "Server error generating interview." });
    }
});

// --- 3. SUBMIT INTERVIEW ---
router.post('/interview/submit', async (req, res) => {
    const { user_id, job_id, answers } = req.body;
    const client = await pool.connect();

    try {
        await client.query('BEGIN');
        let correctCount = 0;

        for (let ans of answers) {
            const qRes = await client.query('SELECT correct_index FROM job_interviews WHERE question_id = $1', [ans.question_id]);
            if (qRes.rows.length > 0 && qRes.rows[0].correct_index === ans.selected_index) {
                correctCount++;
            }
        }

        const passed = correctCount >= 4;

        if (passed) {
            await client.query('UPDATE users SET current_job_id = $1 WHERE user_id = $2', [job_id, user_id]);
            await client.query(`
                INSERT INTO user_job_data (user_id, job_id, current_rank, ban_expiry)
                VALUES ($1, $2, 1, NULL)
                ON CONFLICT (user_id, job_id)
                DO UPDATE SET ban_expiry = NULL
            `, [user_id, job_id]);

            await client.query('COMMIT');
            res.json({ success: true, passed: true, score: correctCount, message: "Welcome to the team. Don't be late." });
        } else {
            await client.query(`
                INSERT INTO user_job_data (user_id, job_id, ban_expiry)
                VALUES ($1, $2, NOW() + INTERVAL '24 hours')
                ON CONFLICT (user_id, job_id)
                DO UPDATE SET ban_expiry = NOW() + INTERVAL '24 hours'
            `, [user_id, job_id]);

            await client.query('COMMIT');
            res.json({ success: true, passed: false, score: correctCount, message: "We went with another candidate. Try again in 24 hours." });
        }
    } catch (err) {
        await client.query('ROLLBACK');
        console.error(err);
        res.status(500).json({ error: "Server error grading interview." });
    } finally {
        client.release();
    }
});

// --- 4. PROMOTE ---
router.post('/promote', async (req, res) => {
    const { user_id } = req.body;
    const client = await pool.connect();

    try {
        await client.query('BEGIN');

        const userRes = await client.query(`
            SELECT current_job_id, stat_acu, stat_ops, stat_pre, stat_res
            FROM users WHERE user_id = $1 FOR UPDATE
        `, [user_id]);
        const user = userRes.rows[0];

        if (!user.current_job_id) throw new Error("You are unemployed.");

        const jobDataRes = await client.query(`
            SELECT current_rank, incentive_balance
            FROM user_job_data WHERE user_id = $1 AND job_id = $2 FOR UPDATE
        `, [user_id, user.current_job_id]);
        const jobData = jobDataRes.rows[0];

        if (jobData.current_rank >= 5) {
            await client.query('ROLLBACK');
            return res.status(400).json({ error: "You are already at the top of the corporate ladder." });
        }

        const nextRankLevel = jobData.current_rank + 1;

        // Fetch Next Rank Requirements (Which now checks ALL 4 stats!)
        const rankRes = await client.query(`
            SELECT stat_req_value, promotion_incentive_cost
            FROM job_ranks WHERE job_id = $1 AND rank_level = $2
        `, [user.current_job_id, nextRankLevel]);
        const nextRank = rankRes.rows[0];

        // GDD: If we updated job_ranks to have 4 stat columns, we check them here.
        // For now, checking the primary stat threshold as a baseline to prevent crashing.
        const masterRes = await client.query('SELECT primary_stat FROM jobs_master WHERE job_id = $1', [user.current_job_id]);
        const primaryStatColumn = 'stat_' + masterRes.rows[0].primary_stat;

        if (user[primaryStatColumn] < nextRank.stat_req_value) {
            await client.query('ROLLBACK');
            return res.status(400).json({ error: "Your Working Stats are too low for promotion." });
        }

        if (jobData.incentive_balance < nextRank.promotion_incentive_cost) {
            await client.query('ROLLBACK');
            return res.status(400).json({ error: "Not enough Job Points for promotion." });
        }

        await client.query(`
            UPDATE user_job_data
            SET current_rank = current_rank + 1,
                incentive_balance = incentive_balance - $1,
                is_mastered = CASE WHEN current_rank + 1 = 5 THEN true ELSE false END
            WHERE user_id = $2 AND job_id = $3
        `, [nextRank.promotion_incentive_cost, user_id, user.current_job_id]);

        await client.query('COMMIT');
        res.json({ success: true, message: `Congratulations on your promotion to Rank ${nextRankLevel}!` });

    } catch (err) {
        await client.query('ROLLBACK');
        console.error(err);
        res.status(500).json({ error: err.message || "Server error during promotion." });
    } finally {
        client.release();
    }
});

// --- 5. RESIGN FROM JOB (CLEAN EXIT VS HEIST) ---
router.post('/quit', async (req, res) => {
    const { user_id, exit_type } = req.body;
    const client = await pool.connect();

    try {
        await client.query('BEGIN');

        const userRes = await client.query('SELECT current_job_id FROM users WHERE user_id = $1 FOR UPDATE', [user_id]);
        const user = userRes.rows[0];

        if (!user.current_job_id) throw new Error("You are already unemployed.");

        const jobId = user.current_job_id;

        const jobDataRes = await client.query('SELECT current_rank, incentive_balance FROM user_job_data WHERE user_id = $1 AND job_id = $2 FOR UPDATE', [user_id, jobId]);
        const jobData = jobDataRes.rows[0];

        if (exit_type === 'clean') {
            // Cut incentives in half and save them, wipe job ID
            await client.query(`
                UPDATE user_job_data
                SET incentive_balance = FLOOR(incentive_balance / 2)
                WHERE user_id = $1 AND job_id = $2
            `, [user_id, jobId]);

            await client.query('UPDATE users SET current_job_id = NULL WHERE user_id = $1', [user_id]);

            await client.query('COMMIT');
            return res.json({ success: true, message: "You put in your two weeks and had a clean exit. 50% of your points were saved." });

        } else if (exit_type === 'heist') {
            // Heist Logic per GDD
            const heistPayout = jobData.current_rank * 10000;

            await client.query(`
                UPDATE user_job_data
                SET incentive_balance = 0, ban_expiry = NOW() + INTERVAL '30 days'
                WHERE user_id = $1 AND job_id = $2
            `, [user_id, jobId]);

            await client.query(`
                UPDATE users
                SET current_job_id = NULL, dirty_cash = dirty_cash + $1, heat = 100
                WHERE user_id = $2
            `, [heistPayout, user_id]);

            await client.query('COMMIT');
            return res.json({ success: true, message: `You burned the place down. Stole $${heistPayout} Dirty Cash. You have max heat and are banned for 30 days.` });

        } else {
            throw new Error("Invalid exit strategy.");
        }

    } catch (err) {
        await client.query('ROLLBACK');
        console.error(err);
        res.status(500).json({ error: err.message || "Server error during resignation." });
    } finally {
        client.release();
    }
});

// --- 6. JOB SPECIALS EXCHANGE ---
router.post('/exchange', async (req, res) => {
    const { user_id, amount } = req.body;
    const client = await pool.connect();

    try {
        await client.query('BEGIN');

        if (amount < 1) throw new Error("Invalid exchange amount.");

        const userRes = await client.query('SELECT current_job_id, hp FROM users WHERE user_id = $1 FOR UPDATE', [user_id]);
        const user = userRes.rows[0];

        if (!user.current_job_id) throw new Error("You must be employed to use specials.");

        const jobDataRes = await client.query('SELECT current_rank, incentive_balance FROM user_job_data WHERE user_id = $1 AND job_id = $2 FOR UPDATE', [user_id, user.current_job_id]);
        const jobData = jobDataRes.rows[0];

        // 1. Verify Special Exists for this Job & Rank
        const jobSpecials = JOB_SPECIALS[user.current_job_id];
        if (!jobSpecials || !jobSpecials[jobData.current_rank]) {
            throw new Error("You do not have an active special at this rank.");
        }

        const special = jobSpecials[jobData.current_rank];
        const totalCost = special.cost * amount;

        // 2. Check Point Balance
        if (jobData.incentive_balance < totalCost) {
            throw new Error(`You need ${totalCost} Job Points. You only have ${jobData.incentive_balance}.`);
        }

        // 3. Deduct Points
        await client.query(`
            UPDATE user_job_data
            SET incentive_balance = incentive_balance - $1
            WHERE user_id = $2 AND job_id = $3
        `, [totalCost, user_id, user.current_job_id]);

        // 4. Execute the Special's Effect
        let responseMessage = "";

        if (special.type === 'heal') {
            const totalHeal = special.heal_amount * amount;
            // Assuming max HP is 100 for now, clamp it.
            await client.query(`
                UPDATE users
                SET hp = LEAST(hp + $1, 100)
                WHERE user_id = $2
            `, [totalHeal, user_id]);
            responseMessage = `Exchanged ${totalCost} points to heal ${totalHeal} HP.`;
        }
        else if (special.type === 'item') {
            const totalItems = special.qty_per_exchange * amount;

            // Insert or update inventory
            await client.query(`
                INSERT INTO user_inventory (user_id, item_id, quantity)
                VALUES ($1, $2, $3)
                ON CONFLICT (user_id, item_id) DO UPDATE SET quantity = user_inventory.quantity + $3
            `, [user_id, special.item_id, totalItems]);

            responseMessage = `Exchanged ${totalCost} points for ${totalItems}x items.`;
        }
        else {
            throw new Error("Special type not fully implemented on server yet.");
        }

        await client.query('COMMIT');
        res.json({ success: true, message: responseMessage });

    } catch (err) {
        await client.query('ROLLBACK');
        console.error(err);
        res.status(500).json({ error: err.message || "Server error exchanging points." });
    } finally {
        client.release();
    }
});

module.exports = router;