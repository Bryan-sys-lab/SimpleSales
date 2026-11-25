import fs from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';

function walk(dir: string): string[] {
  const out: string[] = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (['node_modules', 'dist', '.wrangler', '.git'].includes(entry.name)) continue;
      out.push(...walk(full));
    } else if (/\.(ts|tsx|js|mjs|cjs)$/.test(entry.name)) {
      out.push(full);
    }
  }
  return out;
}

describe('staff JWT guardrails', () => {
  it('keeps staff session token verification centralized', () => {
    const root = path.resolve(__dirname, '..');
    const allowed = new Set([
      path.normalize(path.join(root, 'lib', 'jwt.ts')),
      path.normalize(path.join(root, 'lib', 'staff_session.ts')),
      path.normalize(path.join(__dirname, 'staff_jwt_guard.test.ts')),
    ]);
    const offenders: string[] = [];
    for (const file of walk(root)) {
      const content = fs.readFileSync(file, 'utf8');
      if (content.includes('verifyStaffSessionToken(') && !allowed.has(path.normalize(file))) {
        offenders.push(path.relative(path.resolve(__dirname, '..', '..'), file).replace(/\\/g, '/'));
      }
    }
    expect(offenders).toEqual([]);
  });
});
