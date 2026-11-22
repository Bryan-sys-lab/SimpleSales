import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const root = process.cwd();
const configPath = resolve(root, 'wrangler.jsonc');
const schemaPath = resolve(root, 'prisma', 'schema.prisma');
const schema = readFileSync(schemaPath, 'utf8');
const config = JSON.parse(readFileSync(configPath, 'utf8'));
const envIndex = process.argv.indexOf('--env');
const envName = envIndex >= 0 ? process.argv[envIndex + 1] : undefined;
const target = process.argv.includes('--remote') ? '--remote'
  : process.argv.includes('--local') ? '--local'
    : null;

if (!target) throw new Error('Specify exactly one D1 target: --local or --remote.');
if (envIndex >= 0 && !envName) throw new Error('--env requires an environment name.');

const environment = envName ? config.env?.[envName] : config;
if (!environment) throw new Error(`Wrangler environment "${envName}" is not configured.`);
const d1Binding = environment.d1_databases?.find((binding) => binding.binding === 'DB');
if (!d1Binding?.database_name || !d1Binding.database_id || !d1Binding.migrations_dir) {
  throw new Error(`Wrangler ${envName ? `environment "${envName}"` : 'default environment'} must configure the DB D1 binding and migrations_dir.`);
}

const scalarTypes = new Set(['String', 'Boolean', 'Int', 'BigInt', 'Float', 'Decimal', 'DateTime', 'Json', 'Bytes']);
const models = [...schema.matchAll(/^model\s+(\w+)\s*\{([\s\S]*?)^\}/gm)];
const modelNames = new Set(models.map(([, name]) => name));
const expected = new Map();
for (const [, modelName, body] of models) {
  const tableName = body.match(/^\s*@@map\("([^"]+)"\)/m)?.[1] ?? modelName;
  const columns = new Set();
  for (const line of body.split(/\r?\n/)) {
    const definition = line.replace(/\/\/.*$/, '');
    const field = definition.match(/^\s{2}([A-Za-z_]\w*)\s+([A-Za-z_]\w*)(?:\[\]|\?)?(?:\s|$)/);
    if (!field || !scalarTypes.has(field[2]) || modelNames.has(field[2])) continue;
    const mappedName = definition.match(/@map\("([^"]+)"\)/)?.[1] ?? field[1];
    columns.add(mappedName);
  }
  if (columns.size === 0 || expected.has(tableName)) {
    throw new Error(`Could not derive a unique, non-empty table definition for Prisma model ${modelName}.`);
  }
  expected.set(tableName, columns);
}
if (models.length === 0 || expected.size !== models.length) {
  throw new Error(`Could not derive a unique table definition for every Prisma model (${models.length} models, ${expected.size} tables).`);
}

const migrationRoot = resolve(root, d1Binding.migrations_dir);
const localMigrations = readdirSync(migrationRoot, { withFileTypes: true })
  .filter((entry) => entry.isDirectory() && existsSync(join(migrationRoot, entry.name, 'migration.sql')))
  .map((entry) => `${entry.name}/migration.sql`)
  .sort();
if (localMigrations.length === 0) throw new Error('No Wrangler D1 migration files were found.');

const query = `
  SELECT m.name AS table_name, p.name AS column_name
    FROM sqlite_master AS m
    JOIN pragma_table_info(m.name) AS p
   WHERE m.type = 'table'
     AND m.name NOT LIKE 'sqlite_%'
     AND m.name NOT LIKE '_cf_%'
     AND m.name <> 'd1_migrations'
`;
const wranglerCli = resolve(root, 'node_modules', 'wrangler', 'bin', 'wrangler.js');
const args = [
  wranglerCli,
  'd1',
  'execute',
  d1Binding.database_name,
  target,
  '--command',
  query,
  '--json',
  '--config',
  configPath,
  ...(envName ? ['--env', envName] : []),
];
function executeD1Query(sql) {
  const commandArgs = [...args];
  commandArgs[commandArgs.indexOf('--command') + 1] = sql;
  const result = spawnSync(process.execPath, commandArgs, { cwd: root, encoding: 'utf8' });
  if (result.error) throw new Error(`Could not run Wrangler D1 query: ${result.error.message}`);
  if (result.status !== 0) {
    throw new Error(`Wrangler D1 query failed: ${(result.stderr || result.stdout).trim()}`);
  }
  try {
    const payload = JSON.parse(result.stdout);
    return Array.isArray(payload)
      ? payload.flatMap((entry) => entry.results ?? [])
      : payload.results ?? [];
  } catch {
    throw new Error('Wrangler returned invalid JSON for the D1 query.');
  }
}

const rows = executeD1Query(query);
const actual = new Map();
for (const row of rows) {
  if (!actual.has(row.table_name)) actual.set(row.table_name, new Set());
  actual.get(row.table_name).add(row.column_name);
}
const appliedMigrations = new Set(
  executeD1Query('SELECT name FROM d1_migrations ORDER BY name').map((row) => row.name),
);
const pendingMigrations = localMigrations.filter((name) => !appliedMigrations.has(name));
const unknownMigrations = [...appliedMigrations].filter((name) => !localMigrations.includes(name));

const missingTables = [...expected.keys()].filter((table) => !actual.has(table));
const missingColumns = [];
for (const [table, columns] of expected) {
  for (const column of columns) {
    if (!actual.get(table)?.has(column)) missingColumns.push(`${table}.${column}`);
  }
}
const extraTables = [...actual.keys()].filter((table) => !expected.has(table));
const extraColumns = [];
for (const [table, columns] of actual) {
  for (const column of columns) {
    if (!expected.get(table)?.has(column)) extraColumns.push(`${table}.${column}`);
  }
}

console.log(`Prisma tables/columns present in D1: ${expected.size - missingTables.length}/${expected.size} tables; ${[...expected.values()].reduce((sum, columns) => sum + columns.size, 0) - missingColumns.length} expected columns.`);
if (missingTables.length) console.error(`Missing tables: ${missingTables.join(', ')}`);
if (missingColumns.length) console.error(`Missing columns: ${missingColumns.join(', ')}`);
if (extraTables.length) console.error(`Unmodeled tables: ${extraTables.join(', ')}`);
if (extraColumns.length) console.error(`Unmodeled columns: ${extraColumns.join(', ')}`);
if (pendingMigrations.length) console.error(`Unapplied D1 migrations: ${pendingMigrations.join(', ')}`);
if (unknownMigrations.length) console.error(`Unknown D1 migrations: ${unknownMigrations.join(', ')}`);

if (missingTables.length || missingColumns.length || extraTables.length || extraColumns.length || pendingMigrations.length || unknownMigrations.length) {
  process.exitCode = 1;
} else {
  console.log(`All ${expected.size} Prisma tables, their columns, and ${appliedMigrations.size} D1 migrations match this checkout.`);
}
