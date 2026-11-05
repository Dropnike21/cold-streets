const SERVICE = 'cold-streets-api';

function cleanString(value, max = 1024) {
    if (value === null || value === undefined) return null;
    const text = String(value).replace(/[\r\n\t]+/g, ' ').trim();
    return text.length <= max ? text : text.slice(0, max) + '…';
}

function cleanFields(fields) {
    const out = {};
    for (const [key, value] of Object.entries(fields || {})) {
        if (value === undefined) continue;
        if (value === null || typeof value === 'boolean' || typeof value === 'number') {
            out[key] = value;
        } else if (typeof value === 'bigint') {
            out[key] = value.toString();
        } else if (value instanceof Date) {
            out[key] = value.toISOString();
        } else {
            out[key] = cleanString(value);
        }
    }
    return out;
}

function write(level, event, fields = {}) {
    const line = JSON.stringify({
        timestamp: new Date().toISOString(),
        level,
        service: SERVICE,
        event: cleanString(event, 128),
        ...cleanFields(fields)
    });
    if (level === 'error') process.stderr.write(line + '\n');
    else process.stdout.write(line + '\n');
}

function errorFields(error) {
    if (!error) return {};
    return {
        error_name: cleanString(error.name || 'Error', 128),
        error_code: error.code ? cleanString(error.code, 128) : undefined,
        error_message: cleanString(error.message || error, 512)
    };
}

module.exports = {
    info(event, fields) { write('info', event, fields); },
    warn(event, fields) { write('warn', event, fields); },
    error(event, fields) { write('error', event, fields); },
    errorFields
};
