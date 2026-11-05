// Historical destructive Gym seeder intentionally retired.
//
// Gym catalog state is source-controlled through recovered catalog migrations.
// Running an imperative TRUNCATE/RESEED script can invalidate foreign keys,
// achievement assumptions, and source fingerprints.
//
// The original implementation remains available in Git history for reference.
throw new Error(
    'seed_gyms.js is retired. Restore Gym catalog data only through reviewed source-backed migrations.'
);
