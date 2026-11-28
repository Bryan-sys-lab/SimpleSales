'use client';

import { FormEvent, useCallback, useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { ShellLayout, useAdminAccess } from '@/components/layout';
import { DataTable } from '@/components/data-table';
import { useAdminLiveRefresh } from '@/components/websocket-provider';

type Report = { id: string; email: string; department: string; role: string; parentKeyId: string | null; revokedAt: string | null; expiresAt: string };
type Task = { id: string; title: string; description: string | null; department: string; status: string; createdBy: string; assigneeKeyId: string; dueAt: string | null; createdAt: string; assignee: Report };
const statuses = ['assigned', 'in_progress', 'blocked', 'done', 'cancelled'];
export default function TasksPage() {
  const { can } = useAdminAccess(); const canAssign = can('tasks:manage');
  const [tasks, setTasks] = useState<Task[]>([]); const [reports, setReports] = useState<Report[]>([]); const [title, setTitle] = useState(''); const [description, setDescription] = useState(''); const [assigneeKeyId, setAssigneeKeyId] = useState(''); const [dueAt, setDueAt] = useState(''); const [error, setError] = useState(''); const [busy, setBusy] = useState(false);
  const load = useCallback(async () => {
    try {
      const [taskResult, reportResult] = await Promise.all([
        fetchJson<{ tasks: Task[] }>('/api/admin/org/tasks'),
        fetchJson<{ reports: Report[] }>('/api/admin/org/reports'),
      ]);
      setTasks(taskResult.tasks); setReports(reportResult.reports.filter(r=>!r.revokedAt && new Date(r.expiresAt)>new Date()));
      setAssigneeKeyId(current=>current || reportResult.reports.find(r=>!r.revokedAt)?.id || '');
      setError('');
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Could not load team work'); }
  }, []);
  useAdminLiveRefresh(load, ['tasks']);
  useEffect(() => { void load(); }, [load]);
  async function create(event: FormEvent) {
    event.preventDefault(); setBusy(true); setError('');
    try { await fetchJson('/api/admin/org/tasks', { method:'POST', body:JSON.stringify({title,description:description||undefined,assigneeKeyId,dueAt:dueAt?new Date(dueAt).toISOString():undefined}) }); setTitle(''); setDescription(''); setDueAt(''); await load(); }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'Could not assign task'); }
    finally { setBusy(false); }
  }
  async function setStatus(task: Task, status: string) {
    try { await fetchJson(`/api/admin/org/tasks/${encodeURIComponent(task.id)}`, { method:'PATCH', body:JSON.stringify({status}) }); await load(); }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'Could not update task'); }
  }
  return <ShellLayout><div className="mx-auto max-w-6xl space-y-6">
    <header><p className="text-sm font-semibold text-accent-800">Work management</p><h1 className="mt-1 text-2xl font-semibold tracking-tight">Team tasks</h1><p className="mt-1 max-w-2xl text-sm text-base-600">Managers assign work to direct reports. Reports see their own tasks; managers can track work through their reporting line.</p></header>
    {error && <p role="alert" className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">{error}</p>}
    {canAssign&&reports.length>0 && <section className="card p-4 sm:p-6"><h2 className="text-lg font-semibold">Assign work</h2><form className="mt-4 space-y-4" onSubmit={create}>
      <div className="grid gap-4 sm:grid-cols-2"><div><label className="label" htmlFor="task-title">Task</label><input id="task-title" className="input" required minLength={3} maxLength={160} value={title} onChange={e=>setTitle(e.target.value)} placeholder="Prepare monthly stock reconciliation" /></div><div><label className="label" htmlFor="assignee">Assign to</label><select id="assignee" className="input" required value={assigneeKeyId} onChange={e=>setAssigneeKeyId(e.target.value)}>{reports.map(r=><option key={r.id} value={r.id}>{r.email} · {r.department} · {r.role.replace('_',' ')}</option>)}</select></div><div><label className="label" htmlFor="due-date">Due date (optional)</label><input id="due-date" type="date" className="input" value={dueAt} onChange={e=>setDueAt(e.target.value)} /></div></div>
      <div><label className="label" htmlFor="task-description">Instructions</label><textarea id="task-description" className="input min-h-24" maxLength={4000} value={description} onChange={e=>setDescription(e.target.value)} placeholder="Add the context and expected outcome." /></div>
      <button className="btn btn-accent min-h-11 w-full sm:w-auto" disabled={busy || !assigneeKeyId}>{busy?'Assigning…':'Assign task'}</button>
    </form></section>}
    <section className="space-y-3"><div><h2 className="text-lg font-semibold">Work queue</h2><p className="text-sm text-base-600">Assignments and progress across your accessible reporting line.</p></div><DataTable caption="Team task queue" columns={[{key:'title',label:'Task'},{key:'assignee',label:'Assigned to'},{key:'department',label:'Department'},{key:'status',label:'Status'},{key:'dueAt',label:'Due'},{key:'createdAt',label:'Assigned'}]} data={tasks} rowKey={t=>t.id} renderCell={(task,key)=>{
      if(key==='title') return <span className="font-medium">{task.title}{task.description&&<small className="block max-w-xs truncate text-base-500">{task.description}</small>}</span>;
      if(key==='assignee') return <span>{task.assignee?.email??'—'}<small className="block text-base-500">{task.assignee?.role?.replace('_',' ')}</small></span>;
      if(key==='status') return <select className="input min-h-10 py-1 text-sm capitalize" aria-label={`Status for ${task.title}`} value={task.status} onChange={e=>void setStatus(task,e.target.value)}>{statuses.filter(s=>s!=='assigned'||task.status==='assigned').map(s=><option key={s} value={s}>{s.replace('_',' ')}</option>)}</select>;
      if(key==='dueAt') return <span>{task.dueAt?new Date(task.dueAt).toLocaleDateString():'—'}</span>;
      if(key==='createdAt') return <span>{new Date(task.createdAt).toLocaleDateString()}</span>;
      return <span>{String(task[key as keyof Task]??'—')}</span>;
    }} emptyMessage={reports.length?'No tasks assigned yet.':'No direct reports are assigned to you.'} /></section>
  </div></ShellLayout>;
}
