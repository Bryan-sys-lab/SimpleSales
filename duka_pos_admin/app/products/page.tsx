'use client';

import { useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { ShellLayout } from '@/components/layout';
import { DataTable } from '@/components/data-table';

type AggProduct = {
  key: string;
  name: string;
  category: string;
  shops: number;
  minPrice: number;
  maxPrice: number;
  totalStock: number;
};
type Coverage = {
  activeProducts: number;
  verifiedGtinProducts: number;
  itemKinds: Record<'good' | 'service' | 'fee' | 'unknown', number>;
  gpcMapping: Record<'mapped' | 'unmapped' | 'unknown' | 'notApplicable' | 'rejected', number>;
  unitMapping: Record<'mapped' | 'unmapped' | 'unknown' | 'notApplicable' | 'rejected', number>;
};

const fmt = (n: number) => new Intl.NumberFormat('en-KE', { style: 'currency', currency: 'KES' }).format(n / 100);

export default function ProductsPage() {
  const [products, setProducts] = useState<AggProduct[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [coverage, setCoverage] = useState<Coverage | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetchJson<{ products: AggProduct[]; total: number; identityCoverage?: Coverage }>('/api/admin/products');
        if (!cancelled) { setProducts(res.products); setCoverage(res.identityCoverage ?? null); }
      } catch (err) {
        if (!cancelled) setError(err instanceof Error ? err.message : 'Failed to load products');
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, []);

  return (
    <ShellLayout>
      <div className="space-y-6">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight text-base-900">Products (aggregated)</h2>
          <p className="text-sm text-base-500">Deduplicated catalog across all shops. Counts show how many shops stock each item.</p>
        </div>
        {error && <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800">{error}</div>}
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <div className="card p-4"><p className="text-xs font-medium text-base-500">Unique products</p><p className="text-lg font-semibold text-base-900">{loading ? '…' : products.length}</p></div>
          <div className="card p-4"><p className="text-xs font-medium text-base-500">Total shops stocking</p><p className="text-lg font-semibold text-base-900">{loading ? '…' : products.reduce((a, p) => a + p.shops, 0)}</p></div>
          <div className="card p-4"><p className="text-xs font-medium text-base-500">Total stock units</p><p className="text-lg font-semibold text-base-900">{loading ? '…' : products.reduce((a, p) => a + p.totalStock, 0)}</p></div>
        </div>
        <section aria-labelledby="identity-coverage-heading" className="space-y-3">
          <div>
            <h3 id="identity-coverage-heading" className="text-base font-semibold text-base-900">Identity and unit coverage</h3>
            <p className="text-sm text-base-500">Tenant-free counts across active catalogue records. Unmapped entries remain available for review.</p>
          </div>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-4">
            <div className="card p-4"><p className="text-xs font-medium text-base-500">Goods / services / fees / unknown</p><p className="mt-2 text-sm tabular-nums">{loading ? '…' : coverage ? `${coverage.itemKinds.good} / ${coverage.itemKinds.service} / ${coverage.itemKinds.fee} / ${coverage.itemKinds.unknown}` : 'Unavailable'}</p></div>
            <div className="card p-4"><p className="text-xs font-medium text-base-500">Product taxonomy mapped</p><p className="mt-2 text-sm tabular-nums">{loading ? '…' : coverage ? `${coverage.gpcMapping.mapped} mapped · ${coverage.gpcMapping.unmapped} unmapped` : 'Unavailable'}</p></div>
            <div className="card p-4"><p className="text-xs font-medium text-base-500">External units mapped</p><p className="mt-2 text-sm tabular-nums">{loading ? '…' : coverage ? `${coverage.unitMapping.mapped} mapped · ${coverage.unitMapping.unmapped} unmapped` : 'Unavailable'}</p></div>
            <div className="card p-4"><p className="text-xs font-medium text-base-500">Valid supplier GTINs</p><p className="mt-2 text-sm tabular-nums">{loading ? '…' : coverage ? coverage.verifiedGtinProducts : 'Unavailable'}</p></div>
          </div>
        </section>
        <DataTable
          columns={[
            { key: 'name', label: 'Product', sortable: true },
            { key: 'category', label: 'Category', sortable: true },
            { key: 'shops', label: 'Shops stocking', sortable: true, align: 'right' },
            { key: 'priceRange', label: 'Price range', align: 'right' },
            { key: 'totalStock', label: 'Total stock', sortable: true, align: 'right' },
          ]}
          data={products}
          rowKey={(p) => p.key}
          renderCell={(row, key) => {
            if (key === 'name') return <span className="text-base-900 font-medium">{row.name}</span>;
            if (key === 'category') return <span className="text-base-600">{row.category}</span>;
            if (key === 'shops') return <span className="font-mono tabular-nums">{row.shops}</span>;
            if (key === 'priceRange') return <span className="font-mono tabular-nums text-base-600">{fmt(row.minPrice)} – {fmt(row.maxPrice)}</span>;
            if (key === 'totalStock') return <span className="font-mono tabular-nums">{row.totalStock}</span>;
            return null;
          }}
          emptyMessage={loading ? 'Loading products…' : 'No products found'}
        />
      </div>
    </ShellLayout>
  );
}
