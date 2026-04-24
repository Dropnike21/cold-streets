const express = require('express');
const pool = require('../db');
const router = express.Router();

// Fetch all upgrades for a specific user
router.get('/:user_id', async (req, res) => {
    try {
        const { user_id } = req.params;

        const query = `
            SELECT
                cm.upgrade_id,
                cm.category,
                cm.title,
                cm.description,
                cm.max_level,
                cm.val_per_level,
                cm.suffix,
                COALESCE(uu.current_level, 0) AS current_level
            FROM credit_upgrades_master cm
            LEFT JOIN user_credit_upgrades uu
                ON cm.upgrade_id = uu.upgrade_id AND uu.user_id = $1
            ORDER BY cm.category DESC, cm.upgrade_id ASC;
        `;

        const { rows } = await pool.query(query, [user_id]);

        // Format the data for Flutter so it's incredibly easy to build the UI
        const mappedUpgrades = rows.map(upg => {
            let lvl = Number(upg.current_level);
            let isMaxed = lvl >= upg.max_level;

            // The cost is always exactly the next level number!
            let nextCost = isMaxed ? 0 : lvl + 1;

            let curBonus = lvl * Number(upg.val_per_level);
            let nextBonus = (lvl + 1) * Number(upg.val_per_level);

            return {
                id: upg.upgrade_id,
                category: upg.category,
                title: upg.title,
                description: upg.description,
                level: lvl,
                max_level: upg.max_level,
                is_maxed: isMaxed,
                cost: nextCost,
                current_bonus: `+${curBonus}${upg.suffix}`,
                next_bonus: `+${nextBonus}${upg.suffix}`
            };
        });

        res.json({ success: true, upgrades: mappedUpgrades });

    } catch (err) {
        console.error("Broker Fetch Error:", err.message);
        res.status(500).json({ error: "Failed to load Credit Broker." });
    }
});

module.exports = router;