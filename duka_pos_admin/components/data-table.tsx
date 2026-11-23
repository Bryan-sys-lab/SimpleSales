'use client';

import { useCallback, useMemo, useState } from 'react';
import { EmptyState } from '@/components/empty-state';

type SortDirection = 'asc' | 'desc';

export interface DataTableProps<T> {
  columns: { key: string; label: string; sortable?: boolean; align?: 'left' | 'right' | 'center' }[];
  data: T[];
  rowKey: (row: T) => string | number;
  renderCell: (row: T, key: string) => React.ReactNode;
  emptyMessage?: string;
  className?: string;
  pageSize?: number;
  onRowClick?: (row: T) => void;
}

export function DataTable<T>({
  columns,
  data,
  rowKey,
  renderCell,
  emptyMessage = 'No data available',
  className,
  pageSize = 25,
  onRowClick,
}: DataTableProps<T>) {
  const [sortKey, setSortKey] = useState<string | null>(null);
  const [sortDir, setSortDir] = useState<SortDirection>('asc');
  const [page, setPage] = useState(1);

  const sortableColumns = columns.filter((c) => c.sortable);

  const sorted = useMemo(() => {
    if (!sortKey) return data;
    const dir = sortDir === 'asc' ? 1 : -1;
    return [...data].sort((a, b) => {
      const av = (a as unknown as Record<string, unknown>)[sortKey];
      const bv = (b as unknown as Record<string, unknown>)[sortKey];
      if (av === bv) return 0;
      if (av == null) return dir;
      if (bv == null) return -dir;
      if (typeof av === 'string' && typeof bv === 'string') {
        return av.localeCompare(bv, undefined, { numeric: true }) * dir;
      }
      const an = Number(av);
      const bn = Number(bv);
      if (Number.isFinite(an) && Number.isFinite(bn)) {
        return (an - bn) * dir;
      }
      return String(av).localeCompare(String(bv), undefined, { numeric: true }) * dir;
    });
  }, [data, sortKey, sortDir]);

  const totalPages = Math.max(1, Math.ceil(sorted.length / pageSize));
  const currentPage = Math.min(Math.max(page, 1), totalPages);
  const start = (currentPage - 1) * pageSize;
  const pageData = sorted.slice(start, start + pageSize);

  const handleSort = useCallback(
    (key: string) => {
      if (sortKey === key) {
        setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'));
      } else {
        setSortKey(key);
        setSortDir('asc');
      }
      setPage(1);
    },
    [sortKey],
  );

  const handlePage = useCallback((delta: number) => {
    setPage((p) => Math.min(Math.max(p + delta, 1), totalPages));
  }, [totalPages]);

  return (
    <div className={className}>
      <div className="hidden md:block table-wrap">
        <table className="table">
          <thead>
            <tr>
              {columns.map((col) => (
                <th
                  key={col.key}
                  aria-sort={sortKey === col.key ? (sortDir === 'asc' ? 'ascending' : 'descending') : undefined}
                  className={`
                    ${col.align === 'right' ? 'text-right' : col.align === 'center' ? 'text-center' : 'text-left'}
                  `}
                >
                  {col.sortable ? <button type="button" className="inline-flex min-h-8 items-center gap-1.5 text-left" onClick={() => handleSort(col.key)}>
                    {col.label}
                    <span className="text-base-500" aria-hidden="true">{sortKey === col.key ? (sortDir === 'asc' ? '▲' : '▼') : '↕'}</span>
                  </button> : col.label}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {pageData.length === 0 ? (
              <tr>
                <td colSpan={columns.length} className="text-center">
                  <EmptyState message={emptyMessage} compact />
                </td>
              </tr>
            ) : (
              pageData.map((row) => (
                <tr
                  key={rowKey(row)}
                  className={`group ${onRowClick ? 'cursor-pointer hover:bg-base-100 transition-colors' : ''}`}
                  tabIndex={onRowClick ? 0 : undefined}
                  aria-label={onRowClick ? `Open record ${rowKey(row)}` : undefined}
                  onClick={() => onRowClick?.(row)}
                  onKeyDown={(event) => { if (onRowClick && (event.key === 'Enter' || event.key === ' ')) { event.preventDefault(); onRowClick(row); } }}
                >
                  {columns.map((col) => (
                    <td
                      key={col.key}
                      className={`
                        ${col.align === 'right' ? 'text-right font-mono tabular-nums' : col.align === 'center' ? 'text-center' : 'text-left'}
                      `}
                    >
                      {renderCell(row, col.key)}
                    </td>
                  ))}
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
      <div className="space-y-3 md:hidden" aria-label="Records">
        {pageData.length === 0 ? (
          <div className="rounded-xl border border-base-200 bg-white px-4">
            <EmptyState message={emptyMessage} compact />
          </div>
        ) : pageData.map((row) => {
          const key = rowKey(row);
          const primary = columns.slice(0, Math.min(columns.length, 2));
          const details = columns.slice(primary.length);
          return (
            <details key={key} className="mobile-record">
              <summary onClick={() => onRowClick?.(row)}>
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0 flex-1 space-y-2">
                    {primary.map((col) => <div key={col.key} className="min-w-0">
                      <span className="mb-0.5 block text-[11px] font-semibold uppercase tracking-wide text-base-500">{col.label}</span>
                      <div className="truncate text-sm text-base-900">{renderCell(row, col.key)}</div>
                    </div>)}
                  </div>
                  <span className="mt-1 shrink-0 text-sm font-medium text-accent-800">Details <span aria-hidden="true">⌄</span></span>
                </div>
              </summary>
              {details.length > 0 && <dl className="mt-4 space-y-3 border-t border-base-200 pt-4">
                {details.map((col) => <div key={col.key} className="grid grid-cols-[minmax(7rem,0.8fr)_minmax(0,1.2fr)] items-start gap-3">
                  <dt className="text-xs font-medium text-base-500">{col.label}</dt>
                  <dd className="min-w-0 text-right text-sm text-base-900">{renderCell(row, col.key)}</dd>
                </div>)}
              </dl>}
            </details>
          );
        })}
      </div>
      {sorted.length > pageSize && (
        <div className="mt-4 flex items-center justify-between gap-2 text-sm text-base-600">
          <span>
            Showing {start + 1}–{Math.min(start + pageData.length, sorted.length)} of {sorted.length}
          </span>
          <div className="flex items-center gap-1">
            <button
              onClick={() => handlePage(-1)}
              disabled={currentPage === 1}
              className="rounded-md px-2.5 py-1.5 text-base-600 disabled:opacity-50 disabled:pointer-events-none hover:bg-base-100 focus:outline-none focus:ring-2 focus:ring-base-900"
              aria-label="Previous page"
            >
              <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <polyline points="15 18 9 12 15 6"/>
              </svg>
            </button>
            <span className="px-2">{currentPage} / {totalPages}</span>
            <button
              onClick={() => handlePage(1)}
              disabled={currentPage === totalPages}
              className="rounded-md px-2.5 py-1.5 text-base-600 disabled:opacity-50 disabled:pointer-events-none hover:bg-base-100 focus:outline-none focus:ring-2 focus:ring-base-900"
              aria-label="Next page"
            >
              <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <polyline points="9 18 15 12 9 6"/>
              </svg>
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
