'use client';

import { useCallback, useMemo, useState } from 'react';

type SortDirection = 'asc' | 'desc';

export interface DataTableProps<T> {
  columns: { key: string; label: string; sortable?: boolean; align?: 'left' | 'right' | 'center' }[];
  data: T[];
  rowKey: (row: T) => string | number;
  renderCell: (row: T, key: string) => React.ReactNode;
  emptyMessage?: string;
  className?: string;
  pageSize?: number;
}

export function DataTable<T>({
  columns,
  data,
  rowKey,
  renderCell,
  emptyMessage = 'No data available',
  className,
  pageSize = 25,
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
      <div className="table-wrap">
        <table className="table">
          <thead>
            <tr>
              {columns.map((col) => (
                <th
                  key={col.key}
                  className={`
                    ${col.sortable ? 'cursor-pointer select-none active:scale-95' : ''}
                    ${col.align === 'right' ? 'text-right' : col.align === 'center' ? 'text-center' : 'text-left'}
                  `}
                  onClick={() => col.sortable && handleSort(col.key)}
                >
                  <span className="flex items-center gap-1.5">
                    {col.label}
                    {col.sortable && sortKey === col.key && (
                      <span className="text-base-400">
                        {sortDir === 'asc' ? '▲' : '▼'}
                      </span>
                    )}
                  </span>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {pageData.length === 0 ? (
              <tr>
                <td colSpan={columns.length} className="text-center py-6 text-base-500">
                  {emptyMessage}
                </td>
              </tr>
            ) : (
              pageData.map((row) => (
                <tr key={rowKey(row)} className="group">
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
