'use client';

import { useEffect, useState } from 'react';
import { fetchJson } from '@/lib/api';
import { ShellLayout } from '@/components/layout';
import { useAdminLiveRefresh } from '@/components/websocket-provider';

type Announcement = { id: string; title: string; body: string; active?: boolean } | null;

export default function AnnouncementsPage() {
  const [announcement, setAnnouncement] = useState<Announcement>(null);
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [active, setActive] = useState(true);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetchJson<{ announcement: Announcement }>('/api/admin/announcement');
      setAnnouncement(res.announcement);
      if (res.announcement) {
        setTitle(res.announcement.title);
        setBody(res.announcement.body);
        setActive(res.announcement.active ?? true);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load announcement');
    } finally {
      setLoading(false);
    }
  };

  useAdminLiveRefresh(load, ['announcements']);
  useEffect(() => { void load(); }, []);

  const save = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setMessage(null);
    setError(null);
    try {
      await fetchJson('/api/admin/announcement', {
        method: 'POST',
        body: JSON.stringify({ title, body, active }),
      });
      setMessage('Announcement published to all clients.');
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to publish');
    } finally {
      setSaving(false);
    }
  };

  const clear = async () => {
    setSaving(true);
    setMessage(null);
    setError(null);
    try {
      await fetchJson('/api/admin/announcement', { method: 'DELETE' });
      setAnnouncement(null);
      setTitle('');
      setBody('');
      setMessage('Announcement cleared.');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to clear');
    } finally {
      setSaving(false);
    }
  };

  return (
    <ShellLayout>
      <div className="space-y-6 max-w-3xl">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight text-base-900">Platform announcements</h2>
          <p className="text-sm text-base-500">Broadcast a message to all connected clients in real time.</p>
        </div>
        {error && <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-800">{error}</div>}
        {message && <div className="rounded-xl border border-accent-200 bg-accent-50 px-4 py-3 text-sm text-accent-800">{message}</div>}
        {announcement && (
          <div className="card p-5 space-y-2">
            <p className="text-xs uppercase tracking-wide text-base-500">Current announcement</p>
            <h3 className="text-lg font-semibold text-base-900">{announcement.title}</h3>
            <p className="text-sm text-base-700">{announcement.body}</p>
            <button className="button-secondary" onClick={clear} disabled={saving}>Clear announcement</button>
          </div>
        )}
        <form onSubmit={save} className="card space-y-4 p-5">
          <h3 className="font-semibold">{announcement ? 'Update announcement' : 'New announcement'}</h3>
          <input className="input" required placeholder="Title" value={title} onChange={(e) => setTitle(e.target.value)} />
          <textarea className="input" required rows={4} placeholder="Body" value={body} onChange={(e) => setBody(e.target.value)} />
          <label className="flex items-center gap-2 text-sm text-base-700">
            <input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} />
            Active (broadcast to clients)
          </label>
          <button className="button-primary" type="submit" disabled={saving}>{saving ? 'Publishing…' : 'Publish announcement'}</button>
        </form>
      </div>
    </ShellLayout>
  );
}
