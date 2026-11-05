'use strict';

const express = require('express');
const router = express.Router();
const pool = require('../db');
const { ActionError, integer, sendActionError } = require('../utils/economyValidation');

// Read-only reconciliation. Exact product-name matches are evidence of
// spelling overlap, NOT approved mappings or permission to settle production.
router.get('/:type_id', async (req, res) => {
    try {
        const typeId = integer(req.params.type_id, {
            field: 'Company type ID', min: 1n, max: 9223372036854775807n
        }).toString();

        const company = await pool.query(
            `SELECT type_id, industry_type, tier
               FROM company_types_master
              WHERE type_id = $1`,
            [typeId]
        );
        if (company.rowCount !== 1) {
            throw new ActionError(404, 'Company type not found.');
        }

        const [rules, affiliations, totals] = await Promise.all([
            pool.query(
                `SELECT r.rule_id, r.tier, r.relation_type, r.product_name,
                        r.clean_ratio::text AS source_clean_ratio,
                        r.semantics_status,
                        p.product_id AS legacy_product_id,
                        p.product_name AS legacy_product_name
                   FROM company_product_rules_master r
                   LEFT JOIN company_products_master p
                     ON p.product_name = r.product_name
                  WHERE r.type_id = $1
                  ORDER BY r.rule_id, p.product_id`,
                [typeId]
            ),
            pool.query(
                `SELECT affiliation_id, direction, source_ordinal,
                        related_company_name, related_type_id, resolution_status
                   FROM company_affiliations_master
                  WHERE type_id = $1
                  ORDER BY affiliation_id`,
                [typeId]
            ),
            pool.query(
                `SELECT
                     (SELECT COUNT(*)::bigint FROM company_products_master)::text
                       AS legacy_catalog_products,
                     (SELECT COUNT(*)::bigint
                        FROM company_source_products_master)::text
                       AS source_distinct_products,
                     (SELECT COUNT(*)::bigint
                        FROM company_source_inventory)::text
                       AS source_inventory_rows,
                     (SELECT COUNT(*)::bigint
                        FROM company_product_rules_master)::text
                       AS source_rules_total,
                     (SELECT COUNT(*)::bigint
                        FROM company_affiliations_master
                       WHERE resolution_status <> 'exact')::text
                       AS global_unresolved_affiliations`
            )
        ]);

        const byRule = new Map();
        for (const row of rules.rows) {
            const key = String(row.rule_id);
            if (!byRule.has(key)) {
                byRule.set(key, {
                    rule_id: key,
                    tier: row.tier,
                    relation_type: row.relation_type,
                    product_name: row.product_name,
                    source_clean_ratio: row.source_clean_ratio,
                    semantics_status: row.semantics_status,
                    exact_legacy_name_matches: []
                });
            }
            if (row.legacy_product_id != null) {
                byRule.get(key).exact_legacy_name_matches.push({
                    product_id: String(row.legacy_product_id),
                    product_name: row.legacy_product_name
                });
            }
        }

        const auditedRules = Array.from(byRule.values());
        const unmatched = auditedRules.filter(
            rule => rule.exact_legacy_name_matches.length === 0
        ).length;
        const ambiguous = auditedRules.filter(
            rule => rule.exact_legacy_name_matches.length > 1
        ).length;

        return res.json({
            success: true,
            audit_status: 'read_only_unresolved',
            company_type: company.rows[0],
            global_catalog: totals.rows[0],
            rules_total: auditedRules.length,
            rules_without_exact_legacy_name: unmatched,
            rules_with_multiple_exact_legacy_names: ambiguous,
            unresolved_affiliation_count: affiliations.rows.filter(
                row => row.resolution_status !== 'exact'
            ).length,
            product_rules: auditedRules,
            affiliations: affiliations.rows,
            source_product_namespace_ready: true,
            source_inventory_storage_ready: true,
            source_inventory_mutation_available: false,
            legacy_name_matches_are_approved_mappings: false,
            incorporation_available: false,
            production_available: false,
            stock_ordering_available: false,
            sales_settlement_available: false,
            blockers: [
                'Source supply-chain names and legacy product IDs belong to conflicting catalog generations.',
                'The source-native product namespace is canonical for recovered supply-chain names, but no legacy product-ID mapping has been approved.',
                'Recipe quantities, production cadence, losses and inventory settlement remain unresolved.',
                'Tier-3 clean_ratio does not establish a cash denomination or settlement formula.',
                'Three cross-company affiliation names remain unresolved at the global catalog level.'
            ]
        });
    } catch (err) {
        return sendActionError(res, err, 'Company supply-chain audit failed:');
    }
});

module.exports = router;
