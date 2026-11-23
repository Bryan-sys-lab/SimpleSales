'use client';

import { useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { AppSession } from '@/lib/types';
import { ShellLayout } from '@/components/layout';
import { DataTable } from '@/components/data-table';
import { useWebSocket } from '@/components/websocket-provider';
import { EmptyState } from '@/components/empty-state';

type ReplayEvent = { id: string; name: string; route: string | null; at: string; deviceId: string | null; message: string | null; kind: string | null; action: string | null; actorName: string | null; diagnosticId: string | null };
type Replay = { sessionId: string; tenant: { id: string; shopName: string } | null; deviceId: string | null; events: ReplayEvent[] };
export default function SessionsPage() {
  const [data, setData] = useState<AppSession[]>([]); const [loading, setLoading] = useState(true); const [error, setError] = useState(''); const [selected, setSelected] = useState<Replay | null>(null); const [replayLoading, setReplayLoading] = useState(false);
  const { subscribe } = useWebSocket();
  const load = useCallback(async () => {
    setLoading(true);
    try { const result = await fetchJson<{ sessions: AppSession[] }>('/api/admin/sessions?limit=100'); setData(result.sessions); setError(''); }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'Failed to load sessions'); }
    finally { setLoading(false); }
  }, []);
  useEffect(() => {
    void load();
    const unsubscribe = subscribe((message) => {
      if (message && typeof message === 'object' && (message as { type?: unknown }).type === 'session_activity') void load();
    });
    const interval = setInterval(() => void load(), 30000);
    return () => { unsubscribe(); clearInterval(interval); };
  }, [load, subscribe]);
  async function openReplay(id: string) {
    setReplayLoading(true); setSelected(null);
    try { setSelected(await fetchJson<Replay>(`/api/admin/sessions/${encodeURIComponent(id)}/replay`)); }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'Replay is unavailable'); }
    finally { setReplayLoading(false); }
  }
  return <ShellLayout><main className="space-y-6 pb-24">
    <header><p className="text-sm font-semibold text-accent-800">Security and activity</p><h1 className="mt-1 text-2xl font-semibold tracking-tight">App sessions</h1><p className="mt-1 max-w-3xl text-sm text-base-600">Recent authenticated sessions across shops. Open a session to review the ordered screen and feature activity leading up to its last event. No form contents, PINs, or customer details are included.</p></header>
    {error && <p role="alert" className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">{error}</p>}
    <DataTable columns={[{key:'tenant',label:'Shop'},{key:'deviceId',label:'Device'},{key:'eventCount',label:'Events',sortable:true},{key:'createdAt',label:'Started',sortable:true},{key:'lastActivityAt',label:'Last activity',sortable:true},{key:'expiresAt',label:'Session status'}]} data={data} rowKey={row=>row.id} onRowClick={row=>void openReplay(row.id)} renderCell={(row,key)=>{
      if(key==='tenant') return <span className="font-medium">{row.tenant?.shopName??row.tenantId}</span>;
      if(key==='deviceId') return <span className="font-mono text-xs">{row.deviceId??'Unknown device'}</span>;
      if(key==='eventCount') return <span>{row.eventCount} events</span>;
      if(key==='createdAt'||key==='lastActivityAt') return <span className="text-sm">{new Date(row[key]).toLocaleString()}</span>;
      if(key==='expiresAt') return <span className={`badge ${new Date(row.expiresAt)>new Date()?'badge-none':'badge-low'}`}>{new Date(row.expiresAt)>new Date()?'Active':'Ended'}</span>;
      return null;
    }} emptyMessage={loading?'Loading activity…':'No app activity sessions have been reported yet.'} />
    {replayLoading&&<div className="card p-5 text-sm text-base-600">Loading activity replay…</div>}
    {selected&&<section className="card overflow-hidden" aria-live="polite"><div className="flex flex-wrap items-start justify-between gap-3 border-b border-base-200 p-4 sm:p-5"><div><p className="text-xs font-semibold uppercase tracking-wide text-accent-800">Activity replay</p><h2 className="mt-1 text-lg font-semibold">{selected.tenant?.shopName??'Shop session'}</h2><p className="mt-1 font-mono text-xs text-base-500">Device {selected.deviceId??'unknown'}</p></div><button className="button-secondary min-h-10" onClick={()=>setSelected(null)}>Close replay</button></div>
      <ol className="divide-y divide-base-100">{selected.events.map((event,index)=><li key={event.id} className="flex gap-4 p-4 sm:px-5"><span className={`flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-xs font-semibold ${event.kind?'bg-red-100 text-red-900':'bg-accent-100 text-accent-900'}`}>{index+1}</span><div className="min-w-0 flex-1"><p className={`font-medium ${event.kind?'text-red-800':'text-base-900'}`}>{event.name.replaceAll('_',' ')}</p>{event.message&&<p className="mt-1 break-words text-sm text-base-800">{event.message}</p>}<p className="mt-0.5 text-sm text-base-600">{event.route??'App activity'}{event.action?` · ${event.action}`:''}{event.actorName?` · ${event.actorName}`:''}</p>{event.diagnosticId&&<a className="mt-2 inline-block min-h-10 py-2 text-sm font-medium text-accent-800 underline" href="/diagnostics">Open device diagnostics</a>}</div><time className="shrink-0 text-right text-xs text-base-500">{new Date(event.at).toLocaleString()}</time></li>)}</ol>
      {selected.events.length===0&&<EmptyState message="No replay events available for this session." />}
    </section>}
  </main></ShellLayout>;
}
