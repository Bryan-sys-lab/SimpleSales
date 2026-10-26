import { beforeAll, describe, expect, it } from 'vitest';
import type { Express } from 'express';

let app: Express;

beforeAll(async () => {
  process.env.NODE_ENV = 'test';
  process.env.OIDC_ISSUER_URL = 'https://id.example.test/realms/duka';
  process.env.OIDC_AUDIENCE = 'duka-api';
  process.env.DATABASE_URL ??= 'postgresql://localhost:5432/duka_pos_test';
  const module = await import('../index');
  app = module.default;
});

describe('HTTP safety boundaries', () => {
  it('returns a health response without authentication', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app).get('/health');
    expect(response.status).toBe(200);
    expect(response.body.status).toBe('ok');
    expect(response.headers['x-request-id']).toBeTruthy();
  });

  it('rejects protected routes without a bearer token', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app).get('/api/products');
    expect(response.status).toBe(401);
    expect(response.body.error).toBe('Request could not be completed');
    expect(response.body.requestId).toBeTruthy();
  });

  it('keeps whole-workspace backups behind authentication', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app).get('/api/backups/full');
    expect(response.status).toBe(401);
  });

  it('keeps cross-shop portfolio analytics behind authentication', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app).get('/api/tenant/portfolio');
    expect(response.status).toBe(401);
  });

  it('keeps cross-shop activity behind authentication', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app).get('/api/tenant/activity');
    expect(response.status).toBe(401);
  });

  it('keeps remote transaction detail behind authentication', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app).get('/api/reports/sales/remote-sale-1');
    expect(response.status).toBe(401);
  });

  it('keeps customer and credit sync behind authentication', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app).post('/api/credit/sync').send({ customers: [], entries: [] });
    expect(response.status).toBe(401);
  });

  it('keeps sale conflict resolution behind shop authentication and role checks', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app)
      .post('/api/sales/sync/conflicts/resolve')
      .send({ device_id: 'till-1', local_id: 1, resolution: 'void' });
    expect(response.status).toBe(401);
  });

  it('keeps customer and credit pulls behind authentication', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app).get('/api/credit/sync');
    expect(response.status).toBe(401);
  });

  it('keeps offline operational sync behind authentication', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app).post('/api/shifts/sync').send({ shifts: [] });
    const cups = await supertest.default(app).get('/api/shot-cups/sync');
    const stock = await supertest.default(app).post('/api/stock-movements/sync').send({ stockMovements: [] });
    const reorder = await supertest.default(app).post('/api/reorder').send({ localId: 1 });
    const laybys = await supertest.default(app).post('/api/laybys/sync').send({ laybys: [] });
    const exchanges = await supertest.default(app).post('/api/exchanges/sync').send({ exchanges: [] });
    expect(response.status).toBe(401);
    expect(cups.status).toBe(401);
    expect(stock.status).toBe(401);
    expect(reorder.status).toBe(401);
    expect(laybys.status).toBe(401);
    expect(exchanges.status).toBe(401);
  });

  it('allows only explicitly selected-tenant staff bootstrap without a session', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app)
      .post('/api/tenant/staff/authenticate')
      .send({ username: 'amina', pin: '1234' });
    // The route is intentionally reachable on a fresh till, but it refuses to
    // infer a shop from credentials or a missing tenant selection.
    expect(response.status).toBe(400);
    expect(response.body.error).toBe('Shop selection required');
  });

  it('keeps delivery and return uploads behind authentication', async () => {
    const supertest = await import('supertest');
    const delivery = await supertest.default(app).post('/api/purchases').send({ localId: 1 });
    const returned = await supertest.default(app).post('/api/returns').send({ localId: 1 });
    expect(delivery.status).toBe(401);
    expect(returned.status).toBe(401);
  });

  it('keeps offline cash-control sync behind authentication', async () => {
    const supertest = await import('supertest');
    const expense = await supertest.default(app).post('/api/expenses/sync').send({ expenses: [] });
    const movement = await supertest.default(app).post('/api/till-movements/sync').send({ tillMovements: [] });
    const drawer = await supertest.default(app).post('/api/drawer-events/sync').send({ drawerEvents: [] });
    expect(expense.status).toBe(401);
    expect(movement.status).toBe(401);
    expect(drawer.status).toBe(401);
  });

  it('keeps staff catalogue pulls behind authentication', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app).get('/api/tenant/staff');
    expect(response.status).toBe(401);
  });

  it('rejects platform administration without a bearer token', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app).get('/api/system/analytics');
    expect(response.status).toBe(401);
  });

  it('keeps platform announcement publishing behind system administration', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app)
      .post('/api/admin/announcement')
      .send({ title: 'Update', body: 'A new build is ready.' });
    expect(response.status).toBe(401);
  });

  it('keeps the commercial contribution ledger behind system administration', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app).get('/api/admin/commercial/ledger');
    expect(response.status).toBe(401);
    const aggregate = await supertest.default(app).get('/api/admin/commercial/aggregate-preview');
    const quality = await supertest.default(app).get('/api/admin/commercial/quality');
    const withdraw = await supertest.default(app).post('/api/admin/commercial/ledger/record-1/withdraw').send({ reason: 'test' });
    const retention = await supertest.default(app).post('/api/admin/commercial/retention/run').send({});
    expect(aggregate.status).toBe(401);
    expect(quality.status).toBe(401);
    expect(withdraw.status).toBe(401);
    expect(retention.status).toBe(401);
  });

  it('returns JSON for unknown paths', async () => {
    const supertest = await import('supertest');
    const response = await supertest.default(app).get('/does-not-exist');
    expect(response.status).toBe(404);
    expect(response.body.error).toBe('Not found');
  });
});
