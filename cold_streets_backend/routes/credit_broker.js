const express = require('express');
const { createHash } = require('node:crypto');
const pool = require('../db');
const router = express.Router();
const { requireOwnedPlayerParam } = require('../middleware/playerIdentity');
const {
    ActionError, integer, dbInteger, exactJsonAmount, actorId, sendActionError
} = require('../utils/economyValidation');

router.param('user_id', requireOwnedPlayerParam);

const CREDIT_BROKER_CATALOG_FINGERPRINT = '315a202546541b313fdb1679e1545f9e';
const CREDIT_BROKER_CATALOG_ROWS = 18;

function catalogFingerprint(rows) {
    const serialized = rows.map(row => [
        row.upgrade_id,
        row.category,
        row.title,
        row.description,
        row.max_level,
        row.val_per_level,
        row.suffix ?? ''
    ].map(value => String(value ?? '')).join('|')).join('\n');
    return createHash('md5').update(serialized).digest('hex');
}

function assertCatalog(rows) {
    if (rows.length !== CREDIT_BROKER_CATALOG_ROWS ||
        catalogFingerprint(rows) !== CREDIT_BROKER_CATALOG_FINGERPRINT) {
        throw new ActionError(
            503,
            'Credit Broker catalog changed and requires source reconciliation.'
        );
    }

    for (const row of rows) {
        const level = integer(row.current_level, {
            field: 'Credit Broker upgrade level',
            min: 0n,
            max: 1000000n
        });
        const maxLevel = integer(row.max_level, {
            field: 'Credit Broker maximum level',
            min: 1n,
            max: 1000000n
        });
        if (level > maxLevel) {
            throw new ActionError(
                503,
                'Credit Broker ownership data exceeds the recovered catalog maximum.'
            );
        }
    }
}

// ==========================================
// 1. READ-ONLY RECOVERED CATALOG
// ==========================================
router.get('/:user_id', async (req, res) => {
    try {
        const userId = actorId(req);

        const [userRes, upgradesRes] = await Promise.all([
            pool.query('SELECT cred FROM users WHERE user_id = $1', [userId]),
            pool.query(
                `SELECT
                    cm.upgrade_id,
                    cm.category,
                    cm.title,
                    cm.description,
                    cm.max_level,
                    cm.val_per_level,
                    cm.suffix,
                    COALESCE(uu.current_level, 0) AS current_level,
                    (COALESCE(uu.current_level, 0)::numeric * cm.val_per_level)
                        AS current_bonus,
                    ((COALESCE(uu.current_level, 0) + 1)::numeric * cm.val_per_level)
                        AS next_bonus
                 FROM credit_upgrades_master cm
                 LEFT JOIN user_credit_upgrades uu
                   ON cm.upgrade_id = uu.upgrade_id
                  AND uu.user_id = $1
                 ORDER BY cm.upgrade_id ASC`,
                [userId]
            )
        ]);

        if (userRes.rowCount !== 1) {
            throw new ActionError(404, 'Player not found.');
        }

        assertCatalog(upgradesRes.rows);

        const upgrades = upgradesRes.rows.map(row => {
            const level = Number(integer(row.current_level, {
                field: 'Credit Broker upgrade level',
                min: 0n,
                max: 1000000n
            }));
            const maxLevel = Number(integer(row.max_level, {
                field: 'Credit Broker maximum level',
                min: 1n,
                max: 1000000n
            }));

            return {
                id: row.upgrade_id,
                category: row.category,
                title: row.title,
                description: row.description,
                level,
                max_level: maxLevel,
                is_maxed: level >= maxLevel,
                value_per_level: row.val_per_level,
                suffix: row.suffix ?? '',
                current_bonus: row.current_bonus,
                next_bonus: level >= maxLevel ? null : row.next_bonus,
                purchase_available: false,
                cost: null,
                pricing_status: 'unresolved',
                effect_status: 'catalog_only'
            };
        });

        return res.json({
            success: true,
            broker_status: 'catalog_only',
            purchase_available: false,
            pricing_status: 'unresolved',
            effect_application_status: 'unimplemented',
            cred_earning_status: 'unresolved',
            cred: exactJsonAmount(dbInteger(userRes.rows[0].cred, {
                field: 'Cred balance'
            })),
            upgrades
        });
    } catch (err) {
        return sendActionError(res, err, 'Credit Broker fetch failed:');
    }
});

// ==========================================
// 2. PURCHASES REMAIN FAIL-CLOSED
// ==========================================
router.post('/purchase', async (req, res) => {
    try {
        actorId(req);
        throw new ActionError(
            503,
            'Credit Broker purchases are paused until Cred earning, pricing, and upgrade effect semantics are reconciled.'
        );
    } catch (err) {
        return sendActionError(res, err, 'Credit Broker purchase failed:');
    }
});

module.exports = router;
