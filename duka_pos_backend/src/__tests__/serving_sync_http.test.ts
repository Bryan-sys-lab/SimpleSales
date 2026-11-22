import express from "express";
import supertest from "supertest";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  prisma: {
    customer: { findMany: vi.fn() },
    product: { findMany: vi.fn() },
    syncRecord: { upsert: vi.fn() },
  },
  d1: { prepare: vi.fn(), batch: vi.fn() },
}));

vi.mock("../lib/prisma", () => ({
  prisma: mocks.prisma,
  getD1DatabaseBinding: () => mocks.d1,
}));
vi.mock("../middleware/auth", () => ({
  requireRole:
    (..._roles: string[]) =>
    (_req: unknown, _res: unknown, next: () => void) =>
      next(),
}));

describe("serving sync tenant boundary", () => {
  let app: express.Express;
  let operationalSyncRoutes: express.Router;

  beforeAll(async () => {
    operationalSyncRoutes = (await import("../routes/operational_sync")).default;
    app = express();
    app.use(express.json());
    app.use((req, _res, next) => {
      req.user = {
        id: "owner-1",
        tenantId: "tenant-1",
        role: "admin",
        name: "Owner",
      };
      next();
    });
    app.use("/shot-cups", operationalSyncRoutes);
    app.use("/laybys", operationalSyncRoutes);
    app.use(
      (
        error: { status?: number; message?: string },
        _req: unknown,
        res: express.Response,
        _next: unknown,
      ) => {
        res.status(error.status ?? 500).json({ error: error.message });
      },
    );
  });

  beforeEach(() => {
    vi.clearAllMocks();
    mocks.d1.prepare.mockImplementation((sql: string) => ({
      sql,
      bind: (...bindings: unknown[]) => ({ sql, bindings }),
    }));
    mocks.d1.batch.mockImplementation(async (statements: unknown[]) =>
      statements.map(() => ({ results: [{ id: "remote-cup-1" }], meta: { changes: 1 } })));
    mocks.prisma.customer.findMany.mockResolvedValue([{ localUuid: "customer-1" }]);
    mocks.prisma.product.findMany.mockResolvedValue([{ id: "product-1" }]);
  });

  const serving = (productId: string) => ({
    localId: 1,
    productId,
    productName: "Soda",
    label: "Glass",
    unit: "ml",
    capacity: 300,
    price: 100,
    active: true,
    createdAt: "2026-11-17T00:00:00.000Z",
  });

  it("syncs a serving only when its product belongs to the authenticated shop", async () => {
    const response = await supertest(app)
      .post("/shot-cups/sync")
      .send({ shotCups: [serving("product-1")] });

    expect(response.status).toBe(200);
    expect(response.body.synced).toEqual([
      { localId: 1, remoteId: "remote-cup-1" },
    ]);
    expect(mocks.prisma.product.findMany).toHaveBeenCalledWith({
      where: { tenantId: "tenant-1", id: { in: ["product-1"] } },
      select: { id: true },
    });
  });

  it("rejects a serving that references another shop product before writing sync data", async () => {
    mocks.prisma.product.findMany.mockResolvedValue([]);

    const response = await supertest(app)
      .post("/shot-cups/sync")
      .send({ shotCups: [serving("other-shop-product")] });

    expect(response.status).toBe(409);
    expect(response.body.error).toBe("Product is not available in this shop");
    expect(mocks.d1.batch).not.toHaveBeenCalled();
  });

  it("rejects a lay-by whose customer or product belongs to another shop", async () => {
    const layby = {
      localId: 1,
      uuid: "layby-1",
      customerUuid: "other-shop-customer",
      status: "open",
      totalMinor: 1000,
      paidMinor: 0,
      dueAt: "2026-12-17T00:00:00.000Z",
      createdAt: "2026-11-17T00:00:00.000Z",
      staffName: "Owner",
      items: [
        {
          productId: "other-shop-product",
          productName: "Dress",
          variantName: "",
          qty: 1,
          unitPriceMinor: 1000,
          unitCostMinor: 500,
          discountMinor: 0,
          totalMinor: 1000,
        },
      ],
      payments: [],
    };

    mocks.prisma.customer.findMany.mockResolvedValue([]);

    const response = await supertest(app).post("/laybys/sync").send({
      laybys: [layby],
    });

    expect(response.status).toBe(409);
    expect(response.body.error).toBe("Customer is not available in this shop");
    expect(mocks.d1.batch).not.toHaveBeenCalled();

    mocks.prisma.customer.findMany.mockResolvedValue([
      { localUuid: "other-shop-customer" },
    ]);
    mocks.prisma.product.findMany.mockResolvedValue([]);

    const productResponse = await supertest(app)
      .post("/laybys/sync")
      .send({ laybys: [layby] });

    expect(productResponse.status).toBe(409);
    expect(productResponse.body.error).toBe(
      "Product is not available in this shop",
    );
    expect(mocks.d1.batch).not.toHaveBeenCalled();
  });
});
