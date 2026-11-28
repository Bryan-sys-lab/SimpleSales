'use client';

import { useCallback, useId, useMemo, useState } from 'react';
import { EmptyState } from '@/components/empty-state';

type SortDirection = 'asc' | 'desc';
const textCollator = new Intl.Collator(undefined, { numeric: true, sensitivity: 'base' });

function getSortValue(row: unknown, key: string): unknown {
  let value = row;
  for (const part of key.split('.')) {
    if (typeof value !== 'object' || value === null || Array.isArray(value)) return undefined;
    value = (value as Record<string, unknown>)[part];
  }
  return value;
}

export interface DataTableProps<T> {
  caption: string;
  columns: {
    key: string;
    label: string;
    sortable?: boolean;
    align?: 'left' | 'right' | 'center';
    sortValue?: (row: T) => unknown;
  }[];
  data: T[];
  rowKey: (row: T) => string | number;
  renderCell: (row: T, key: string) => React.ReactNode;
  emptyMessage?: string;
  className?: string;
  pageSize?: number;
  onRowClick?: (row: T) => void;
  initialSort?: { key: string; direction: SortDirection };
}

export function DataTable<T>({
  caption,
  columns,
  data,
  rowKey,
  renderCell,
  emptyMessage = 'No data available',
  className,
  pageSize = 25,
  onRowClick,
  initialSort,
}: DataTableProps<T>) {
  const captionId = useId();
  const [sortKey, setSortKey] = useState<string | null>(initialSort?.key ?? null);
  const [sortDir, setSortDir] = useState<SortDirection>(initialSort?.direction ?? 'asc');
  const [page, setPage] = useState(1);
  const [sortAnnouncement, setSortAnnouncement] = useState('');

  const sortableColumns = useMemo(() => columns.filter((c) => c.sortable), [columns]);
  const sortValue = sortableColumns.find((column) => column.key === sortKey)?.sortValue;

  const sorted = useMemo(() => {
    if (!sortKey) return data;
    const dir = sortDir === 'asc' ? 1 : -1;
    return data.toSorted((a, b) => {
      const av = sortValue ? sortValue(a) : getSortValue(a, sortKey);
      const bv = sortValue ? sortValue(b) : getSortValue(b, sortKey);
      if (av === bv) return 0;
      if (av == null) return dir;
      if (bv == null) return -dir;
      if (typeof av === 'number' && typeof bv === 'number') {
        return (av - bv) * dir;
      }
      return textCollator.compare(String(av), String(bv)) * dir;
    });
  }, [data, sortKey, sortDir, sortValue]);

  const totalPages = Math.max(1, Math.ceil(sorted.length / pageSize));
  const currentPage = Math.min(Math.max(page, 1), totalPages);
  const start = (currentPage - 1) * pageSize;
  const pageData = sorted.slice(start, start + pageSize);

  const handleSort = useCallback(
    (key: string, label: string) => {
      const direction = sortKey === key && sortDir === 'asc' ? 'desc' : 'asc';
      setSortKey(key);
      setSortDir(direction);
      setPage(1);
      setSortAnnouncement(`Sorted by ${label}, ${direction === 'asc' ? 'ascending' : 'descending'}, ${data.length} records.`);
    },
    [data.length, sortDir, sortKey],
  );

  const handlePage = useCallback((delta: number) => {
    setPage((p) => Math.min(Math.max(p + delta, 1), totalPages));
  }, [totalPages]);

  return (
    <div className={className ? `data-table-container ${className}` : 'data-table-container'}>
      <p className="sr-only" role="status" aria-live="polite">{sortAnnouncement}</p>
      {sortableColumns.length > 0 && (
        <div className="data-table-mobile-controls mb-3 flex items-end gap-2">
          <div className="min-w-0 flex-1">
            <label className="label" htmlFor={`${captionId}-sort`}>Sort records</label>
            <select
              id={`${captionId}-sort`}
              className="input"
              value={sortKey ?? ''}
              onChange={(event) => {
                const key = event.target.value;
                const column = sortableColumns.find((item) => item.key === key);
                setSortKey(column?.key ?? null);
                setSortDir('asc');
                setPage(1);
                setSortAnnouncement(column ? `Sorted by ${column.label}, ascending, ${data.length} records.` : '');
              }}
            >
              <option value="">Default order</option>
              {sortableColumns.map((column) => <option key={column.key} value={column.key}>{column.label}</option>)}
            </select>
          </div>
          <button
            type="button"
            className="button-secondary min-h-11 shrink-0"
            disabled={!sortKey}
            aria-label={`Change sort order to ${sortDir === 'asc' ? 'descending' : 'ascending'}`}
            onClick={() => {
              const direction = sortDir === 'asc' ? 'desc' : 'asc';
              const label = sortableColumns.find((column) => column.key === sortKey)?.label ?? sortKey;
              setSortDir(direction);
              setPage(1);
              setSortAnnouncement(`Sorted by ${label}, ${direction === 'asc' ? 'ascending' : 'descending'}, ${data.length} records.`);
            }}
          >
            {sortDir === 'asc' ? 'Ascending' : 'Descending'}
          </button>
        </div>
      )}
      <div className="table-wrap data-table-desktop" role="region" aria-labelledby={`${captionId}-caption`} tabIndex={0}>
        <table className="table min-w-[48rem]">
          <caption id={`${captionId}-caption`} className="sr-only">{caption}</caption>
          <thead>
            <tr>
              {columns.map((col) => (
                <th
                  key={col.key}
                  scope="col"
                  aria-sort={sortKey === col.key ? (sortDir === 'asc' ? 'ascending' : 'descending') : undefined}
                  className={`
                    ${col.align === 'right' ? 'text-right' : col.align === 'center' ? 'text-center' : 'text-left'}
                  `}
                >
                  {col.sortable ? <button type="button" className="inline-flex min-h-11 items-center gap-1.5 text-left" onClick={() => handleSort(col.key, col.label)}>
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
                  onClick={(event) => {
                    if (!onRowClick) return;
                    if (event.target instanceof Element && event.target.closest('a, button, input, select, textarea')) return;
                    onRowClick(row);
                  }}
                  onKeyDown={(event) => {
                    if (onRowClick && event.target === event.currentTarget && (event.key === 'Enter' || event.key === ' ')) {
                      event.preventDefault();
                      onRowClick(row);
                    }
                  }}
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
      <ul className="data-table-mobile-records space-y-3" role="list" aria-label={`${caption} records`}>
        {pageData.length === 0 ? (
          <li className="rounded-xl border border-base-200 bg-white px-4">
            <EmptyState message={emptyMessage} compact />
          </li>
        ) : pageData.map((row) => {
          const key = rowKey(row);
          const primary = columns.slice(0, Math.min(columns.length, 2));
          const details = columns.slice(primary.length);
          return (
            <li key={key}>
              <details className="mobile-record">
                <summary>
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0 flex-1 space-y-2">
                      {primary.map((col) => <div key={col.key} className="min-w-0">
                        <span className="mb-0.5 block text-xs font-semibold uppercase tracking-wide text-base-600">{col.label}</span>
                        <div className="truncate text-sm text-base-900">{renderCell(row, col.key)}</div>
                      </div>)}
                    </div>
                    <span className="mt-1 shrink-0 text-sm font-medium text-accent-800">Details <span className="mobile-record-chevron" aria-hidden="true">⌄</span></span>
                  </div>
                </summary>
                {details.length > 0 && <dl className="mt-4 space-y-3 border-t border-base-200 pt-4">
                  {details.map((col) => <div key={col.key} className="grid grid-cols-[minmax(7rem,0.8fr)_minmax(0,1.2fr)] items-start gap-3">
                    <dt className="text-xs font-medium text-base-600">{col.label}</dt>
                    <dd className="min-w-0 break-words text-right text-sm text-base-900">{renderCell(row, col.key)}</dd>
                  </div>)}
                </dl>}
                {onRowClick && <button
                  type="button"
                  className="button-secondary mt-4 w-full"
                  onClick={() => onRowClick(row)}
                  aria-label={`Open record ${key}`}
                >
                  Open record
                </button>}
              </details>
            </li>
          );
        })}
      </ul>
      {sorted.length > pageSize && (
        <div className="mt-4 flex items-center justify-between gap-2 text-sm text-base-700" role="group" aria-label={`${caption} pagination`}>
          <span>
            Showing {start + 1}–{Math.min(start + pageData.length, sorted.length)} of {sorted.length}
          </span>
          <div className="flex items-center gap-1">
            <button
              type="button"
              onClick={() => handlePage(-1)}
              disabled={currentPage === 1}
              className="min-h-11 min-w-11 rounded-md text-base-700 disabled:pointer-events-none disabled:opacity-50 hover:bg-base-100 focus:outline-none focus:ring-2 focus:ring-base-900"
              aria-label="Previous page"
            >
              <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <polyline points="15 18 9 12 15 6"/>
              </svg>
            </button>
            <span className="px-2">{currentPage} / {totalPages}</span>
            <button
              type="button"
              onClick={() => handlePage(1)}
              disabled={currentPage === totalPages}
              className="min-h-11 min-w-11 rounded-md text-base-700 disabled:pointer-events-none disabled:opacity-50 hover:bg-base-100 focus:outline-none focus:ring-2 focus:ring-base-900"
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
