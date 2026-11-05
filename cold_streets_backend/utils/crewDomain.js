const { ActionError } = require('./economyValidation');

// Shared crew-domain transfer guard.
//
// Source-backed rule from the reconciled crew scheduler: moving a recruit
// between different active domains is subject to a 10-minute transfer cooldown.
// Callers must already be inside the mutation transaction.
async function handleCrewDomainTransfer(client, userId, crewId, newDomain) {
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
    if (crewRes.rowCount !== 1) {
        throw new ActionError(404, 'Crew member not found.');
    }

    const crew = crewRes.rows[0];
    const currentDomain = crew.current_domain || 'IDLE';
    const remainingSeconds = crew.transfer_seconds_remaining == null
        ? 0
        : Number(crew.transfer_seconds_remaining);

    if (!Number.isSafeInteger(remainingSeconds) || remainingSeconds < 0) {
        throw new Error('Invalid crew transfer cooldown state.');
    }

    if (
        currentDomain !== 'IDLE' &&
        currentDomain !== newDomain &&
        remainingSeconds > 0
    ) {
        throw new ActionError(
            409,
            'Transfer cooldown active for ' +
                Math.ceil(remainingSeconds / 60) +
                ' more minute(s).'
        );
    }

    if (currentDomain !== newDomain) {
        await client.query(
            `UPDATE user_crew
                SET current_domain = $1,
                    last_transfer_at = NOW()
              WHERE crew_id = $2
                AND user_id = $3`,
            [newDomain, crewId, userId]
        );
    }

    return { currentDomain, remainingSeconds };
}

module.exports = { handleCrewDomainTransfer };
