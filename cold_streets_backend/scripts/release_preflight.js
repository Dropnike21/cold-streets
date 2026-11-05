require('dotenv').config();

const errors = [];
const warnings = [];

const gameplayEnabled = process.env.ENABLE_GAMEPLAY_API === 'true';
const nodeEnv = process.env.NODE_ENV || 'development';

if (process.env.ENABLE_UNSAFE_LEGACY_TIMERS === 'true') {
    errors.push('ENABLE_UNSAFE_LEGACY_TIMERS is retired and must not be enabled.');
}

const origins = (process.env.CORS_ALLOWED_ORIGINS || '')
    .split(',')
    .map(value => value.trim())
    .filter(Boolean);
if (origins.includes('*')) {
    errors.push('CORS_ALLOWED_ORIGINS must not contain a wildcard.');
}

if (gameplayEnabled) {
    const required = [
        'SUPABASE_URL',
        'SUPABASE_PUBLISHABLE_KEY',
        'DB_HOST',
        'DB_USER',
        'DB_PASSWORD',
        'DB_NAME'
    ];
    for (const key of required) {
        if (!process.env[key]) errors.push(key + ' is required when gameplay is enabled.');
    }

    const supabaseUrl = process.env.SUPABASE_URL || '';
    let parsed;
    try {
        parsed = new URL(supabaseUrl);
    } catch (_) {
        errors.push('SUPABASE_URL must be a valid URL.');
    }
    if (parsed && parsed.protocol !== 'https:') {
        errors.push('SUPABASE_URL must use HTTPS.');
    }

    const publishable = process.env.SUPABASE_PUBLISHABLE_KEY || '';
    if (
        publishable.startsWith('sb_secret_') ||
        publishable.toLowerCase().includes('service_role')
    ) {
        errors.push('SUPABASE_PUBLISHABLE_KEY must not contain a secret/service-role key.');
    }

    if (nodeEnv === 'production' && process.env.DB_SSL === 'false') {
        errors.push('DB_SSL=false is forbidden when NODE_ENV=production.');
    }
    if (nodeEnv === 'production' && origins.length === 0) {
        warnings.push('No browser CORS origins are configured; native clients can still omit Origin.');
    }
} else {
    warnings.push('Gameplay API is disabled; only /healthz should be reachable.');
}

if (errors.length) {
    console.error('Cold Streets release preflight failed:');
    for (const error of errors) console.error('- ' + error);
    process.exitCode = 1;
} else {
    console.log('Cold Streets release configuration preflight passed.');
    for (const warning of warnings) console.log('WARN: ' + warning);
}
