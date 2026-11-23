export type AdminLiveResource =
  | 'admins'
  | 'announcements'
  | 'audit'
  | 'billing'
  | 'business-context'
  | 'churn'
  | 'commercial-ledger'
  | 'commercial-policy'
  | 'commercial-quality'
  | 'dashboard'
  | 'diagnostics'
  | 'expenses'
  | 'exchanges'
  | 'financials'
  | 'laybys'
  | 'membership'
  | 'products'
  | 'sales'
  | 'sessions'
  | 'support'
  | 'tax-compliance'
  | 'tax-rules'
  | 'tasks'
  | 'telemetry'
  | 'tenants'
  | 'users';

type LiveEvent = { type?: unknown; resources?: unknown; events?: unknown; at?: unknown; deviceId?: unknown; entries?: unknown };

const RESOURCE_VALUES: Record<string, true> = {
  admins: true,
  announcements: true,
  audit: true,
  billing: true,
  'business-context': true,
  churn: true,
  'commercial-ledger': true,
  'commercial-policy': true,
  'commercial-quality': true,
  dashboard: true,
  diagnostics: true,
  expenses: true,
  exchanges: true,
  financials: true,
  laybys: true,
  membership: true,
  products: true,
  sales: true,
  sessions: true,
  support: true,
  'tax-compliance': true,
  'tax-rules': true,
  tasks: true,
  telemetry: true,
  tenants: true,
  users: true,
};

export function isAdminLiveResource(resource: string): resource is AdminLiveResource {
  return Object.prototype.hasOwnProperty.call(RESOURCE_VALUES, resource);
}

const EVENT_RESOURCES: Record<string, AdminLiveResource[]> = {
  device_diagnostic_reported: ['diagnostics'],
  platform_announcement: ['announcements'],
  platform_announcement_cleared: ['announcements'],
  session_activity: ['sessions'],
  subscription_quote_requested: ['support', 'billing'],
  telemetry_event_ingested: ['telemetry', 'sessions'],
};

export function resourcesForLiveMessage(message: unknown): AdminLiveResource[] {
  if (!message || typeof message !== 'object') return [];
  const event = message as LiveEvent;
  if (event.type === 'admin_data_changed' && Array.isArray(event.resources)) {
    return [...new Set(event.resources.filter((resource): resource is AdminLiveResource =>
      typeof resource === 'string' && isAdminLiveResource(resource),
    ))];
  }
  return typeof event.type === 'string' ? EVENT_RESOURCES[event.type] ?? [] : [];
}
