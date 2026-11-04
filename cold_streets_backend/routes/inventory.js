const express = require('express');
const pool = require('../db');
const router = express.Router();
const { ActionError, integer, actorId, sendActionError } = require('../utils/economyValidation');
const { requireIdempotencyKey, beginIdempotent, completeIdempotent } = require('../utils/idempotency');

const DIRECT_CONSUMABLE_EFFECTS = new Set(['energy_gain', 'energy_restore', 'nerve_gain', 'instant_heal']);

function parseDirectConsumableEffects(source) {
    if (typeof source !== 'string') throw new ActionError(503, 'Consumable effect data is unavailable.');
    const text = source.trim();
    if (!text.startsWith('{') || !text.endsWith('}')) throw new ActionError(503, 'Consumable effect format is unsupported.');
    const body = text.slice(1, -1).trim();
    if (!body || body.includes('{') || body.includes('}')) throw new ActionError(503, 'Consumable mechanics are not yet implemented.');
    const result = {};
    for (const part of body.split(',')) {
        const match = part.trim().match(/^([a-z_]+)\s*:\s*([0-9]+)$/);
        if (!match || !DIRECT_CONSUMABLE_EFFECTS.has(match[1]) || Object.prototype.hasOwnProperty.call(result, match[1])) {
            throw new ActionError(503, 'This consumable mechanic is not yet implemented on the server.');
        }
        const amount = Number(match[2]);
        if (!Number.isSafeInteger(amount) || amount < 0) throw new ActionError(503, 'Consumable effect value is unsupported.');
        result[match[1]] = amount;
    }
    return result;
}
// Reject URLs referencing any player other than the verified session owner.
const { requireOwnedPlayerParam } = require('../middleware/playerIdentity');
router.param('user_id', requireOwnedPlayerParam);


// --- 1. GET PLAYER INVENTORY ---
router.get('/:user_id', async (req, res) => {
    try {
        const { user_id } = req.params;

        // V1.1 Fix: Added GREATEST(..., 1) to strictly enforce the $1 Floor Economy
        const query = `
            SELECT
                ui.inventory_id, ui.quantity, im.*,
                (SELECT COALESCE(SUM(quantity), 0) FROM user_inventory WHERE item_id = im.item_id) + im.stock AS circulation,
                GREATEST(ROUND(im.base_value * (1 + COALESCE(((im.baseline_stock - im.stock)::numeric / NULLIF(im.baseline_stock, 0)) * 0.5, 0))), 1) AS current_value
            FROM user_inventory ui
            JOIN items_master im ON ui.item_id = im.item_id
            WHERE ui.user_id = $1 AND ui.quantity > 0
            ORDER BY im.category ASC, im.name ASC
        `;

        const inventory = await pool.query(query, [user_id]);
        res.json(inventory.rows);
    } catch (err) {
        console.error("Inventory Fetch Error:", err.message);
        res.status(500).json({ error: "Failed to load stash." });
    }
});

// --- 2. USE A CONSUMABLE ITEM ---
// --- 2. USE A CONSUMABLE ITEM (V1.2 JSONB ENGINE) ---
router.post('/use', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const idempotencyKey = requireIdempotencyKey(req);
        const itemId = integer(req.body?.item_id, {
            field: 'Item ID', min: 1n, max: 9223372036854775807n
        }).toString();

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;

        const userCheck = await client.query(
            'SELECT hp, max_hp, energy, nerve, max_nerve FROM users WHERE user_id = $1 FOR UPDATE',
            [userId]
        );
        if (userCheck.rowCount !== 1) throw new ActionError(404, 'Player not found.');
        const idem = await beginIdempotent(
            client, userId, 'inventory.use', idempotencyKey, { itemId }
        );
        if (idem.replay) {
            await client.query('COMMIT');
            transaction = false;
            return res.status(idem.status).json(idem.response);
        }

        const inventory = await client.query(
            `SELECT quantity
               FROM user_inventory
              WHERE user_id = $1 AND item_id = $2
              FOR UPDATE`,
            [userId, itemId]
        );
        if (inventory.rowCount !== 1 || BigInt(inventory.rows[0].quantity) <= 0n) {
            throw new ActionError(409, 'You do not have this item.');
        }
        const itemRes = await client.query(
            `SELECT item_id, name, category, effects, cooldown_type, cooldown_seconds
               FROM items_master
              WHERE item_id = $1`,
            [itemId]
        );
        if (itemRes.rowCount !== 1) throw new ActionError(404, 'Item catalog row missing.');
        const item = itemRes.rows[0];
        if (item.category !== 'CONSUMABLES') throw new ActionError(400, 'This item cannot be consumed.');

        const effects = parseDirectConsumableEffects(item.effects);
        const cooldownType = item.cooldown_type;
        const cooldownSeconds = Number(item.cooldown_seconds || 0);
        if (!Number.isSafeInteger(cooldownSeconds) || cooldownSeconds < 0) {
            throw new Error('Invalid item cooldown in catalog.');
        }
        if (cooldownType && cooldownType !== 'none' && cooldownSeconds > 0) {
            const cooldown = await client.query(
                `SELECT 1 FROM user_cooldowns
                  WHERE user_id = $1 AND type = $2 AND expires_at > NOW()
                  LIMIT 1`,
                [userId, cooldownType]
            );
            if (cooldown.rowCount) {
                throw new ActionError(409, 'A ' + cooldownType + ' cooldown is already active.');
            }
        }

        const heal = effects.instant_heal || 0;
        const energyGain = (effects.energy_gain || 0) + (effects.energy_restore || 0);
        const nerveGain = effects.nerve_gain || 0;
        if (heal === 0 && energyGain === 0 && nerveGain === 0) {
            throw new ActionError(503, 'This consumable has no implemented direct effect.');
        }

        const updatedUser = await client.query(
            `UPDATE users
                SET hp = LEAST(max_hp, hp + $1),
                    energy = LEAST(100, energy + $2),
                    nerve = LEAST(max_nerve, nerve + $3)
              WHERE user_id = $4
              RETURNING dirty_cash, energy, nerve, max_nerve, hp, max_hp`,
            [heal, energyGain, nerveGain, userId]
        );
        if (updatedUser.rowCount !== 1) throw new Error('Player disappeared during item use.');

        const consumed = await client.query(
            `UPDATE user_inventory
                SET quantity = quantity - 1
              WHERE user_id = $1 AND item_id = $2 AND quantity > 0
              RETURNING quantity`,
            [userId, itemId]
        );
        if (consumed.rowCount !== 1) throw new ActionError(409, 'Inventory changed before item use.');
        await client.query(
            'DELETE FROM user_inventory WHERE user_id = $1 AND item_id = $2 AND quantity <= 0',
            [userId, itemId]
        );
        if (cooldownType && cooldownType !== 'none' && cooldownSeconds > 0) {
            await client.query(
                `INSERT INTO user_cooldowns (user_id, type, expires_at, reason)
                 VALUES ($1, $2, NOW() + $3::integer * INTERVAL '1 second', $4)`,
                [userId, cooldownType, cooldownSeconds, 'Used ' + item.name + '.']
            );
        }

        const response = {
            status: 'success',
            message: 'Used ' + item.name + '.',
            user: updatedUser.rows[0]
        };
        await completeIdempotent(client, idem, 200, response);
        await client.query('COMMIT');
        transaction = false;
        return res.json(response);
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); } catch (rollback) { console.error('Item use rollback:', rollback); }
        }
        return sendActionError(res, err, 'Item use failed:');
    } finally { if (client) client.release(); }
});

// --- 3. EQUIP WEAPON / ARMOR ---

router.post('/equip', async (req, res) => {
    let client, transaction = false;
    try {
        const userId = actorId(req);
        const itemId = integer(req.body?.item_id, {
            field: 'Item ID', min: 1n, max: 9223372036854775807n
        }).toString();
        const slot = req.body?.slot;
        const validSlots = {
            primary_weapon_id: 'PRIMARY',
            secondary_weapon_id: 'SECONDARY',
            melee_weapon_id: 'MELEE',
            armor_id: 'ARMOR'
        };
        if (!Object.prototype.hasOwnProperty.call(validSlots, slot)) {
            throw new ActionError(400, 'Invalid equipment slot.');
        }

        client = await pool.connect();
        await client.query('BEGIN');
        transaction = true;
        const player = await client.query(
            'SELECT user_id FROM users WHERE user_id = $1 FOR UPDATE', [userId]
        );
        if (player.rowCount !== 1) throw new ActionError(404, 'Player not found.');
        const inv = await client.query(
            'SELECT quantity FROM user_inventory WHERE user_id = $1 AND item_id = $2 FOR UPDATE',
            [userId, itemId]
        );
        if (inv.rowCount !== 1 || BigInt(inv.rows[0].quantity) <= 0n) {
            throw new ActionError(409, 'You do not own this item.');
        }
        const item = await client.query(
            'SELECT name, category FROM items_master WHERE item_id = $1',
            [itemId]
        );
        if (item.rowCount !== 1) throw new ActionError(404, 'Item catalog row missing.');
        if (item.rows[0].category !== validSlots[slot]) {
            throw new ActionError(400, 'Item category does not match this equipment slot.');
        }

        const equipped = await client.query(
            'UPDATE user_equipment SET ' + slot + ' = $1 WHERE user_id = $2 RETURNING user_id',
            [itemId, userId]
        );
        if (equipped.rowCount !== 1) throw new Error('Player equipment row missing.');
        await client.query('COMMIT');
        transaction = false;
        return res.json({ status: 'success', message: 'Equipped ' + item.rows[0].name + '.' });
    } catch (err) {
        if (transaction) {
            try { await client.query('ROLLBACK'); } catch (rollback) { console.error('Equip rollback:', rollback); }
        }
        return sendActionError(res, err, 'Equip failed:');
    } finally { if (client) client.release(); }
});

module.exports = router;