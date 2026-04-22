// File Path: cold_streets_backend/seed_gyms.js

const pool = require('./db');

async function seedGyms() {
    const zones = ["The Neighborhood", "Downtown District", "The Underground", "High Society", "Cartel Territory"];

    try {
        console.log("🔥 Connecting to Cold Streets DB...");
        await pool.query('BEGIN');

        // Clear the table to prevent duplicates
        await pool.query('TRUNCATE TABLE gyms_master RESTART IDENTITY CASCADE');

        for (let i = 0; i < 40; i++) {
            const gym_id = i + 1;
            const zoneIndex = Math.floor(i / 8);
            const baseMult = 1.0 + (i * 0.15);

            let mStr = baseMult; let mDef = baseMult;
            let mDex = baseMult; let mSpd = baseMult;
            let focus = "Balanced";

            if (i % 3 === 1) { mStr *= 1.5; mDef *= 1.3; mDex *= 0.8; mSpd *= 0.8; focus = "Heavy Iron (STR/DEF)"; }
            else if (i % 3 === 2) { mDex *= 1.5; mSpd *= 1.5; mStr *= 0.8; mDef *= 0.8; focus = "Athletics (DEX/SPD)"; }

            const name = i === 0 ? "Playground Park" : `Gym Facility #${gym_id}`;
            const zone = zones[zoneIndex];
            const desc = i === 0 ? "Rusty pull-up bars and concrete. It's free, but the street gains are slow." : `A localized training facility located in ${zone}.`;

            const unlock_cost = i === 0 ? 0 : 500 * (i * i);
            const daily_fee = i * 50;
            const unlock_exp_req = i === 0 ? 0 : 100 * (i * i);

            // Narrative Actions
            const str_action = i === 0 ? 'did pull-ups on the rusty bars' : 'lifted heavy weights';
            const def_action = i === 0 ? 'hardened your knuckles against the concrete posts' : 'hit the heavy bag';
            const dex_action = i === 0 ? 'practiced shadow boxing near the fountain' : 'practiced form';
            const spd_action = i === 0 ? 'ran around the park trail' : 'ran laps';

            const insertQuery = `
                INSERT INTO gyms_master (
                    gym_id, gym_name, energy_cost, unlock_exp_req, daily_fee, description,
                    mult_str, mult_def, mult_dex, mult_spd, zone, focus, unlock_cost,
                    str_action, def_action, dex_action, spd_action
                ) VALUES ($1, $2, 1, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
            `;

            await pool.query(insertQuery, [
                gym_id, name, unlock_exp_req, daily_fee, desc,
                mStr.toFixed(2), mDef.toFixed(2), mDex.toFixed(2), mSpd.toFixed(2),
                zone, focus, unlock_cost, str_action, def_action, dex_action, spd_action
            ]);
        }

        await pool.query('COMMIT');
        console.log("✅ Successfully populated 40 Gyms into gyms_master!");
        process.exit(0);

    } catch (err) {
        await pool.query('ROLLBACK');
        console.error("❌ Seeding Failed: ", err);
        process.exit(1);
    }
}

seedGyms();