export const adminPermissionOptions = [
  'system:read', 'keys:read', 'keys:manage', 'users:read', 'users:manage',
  'tenants:read', 'tenants:manage', 'sessions:read', 'sessions:manage',
  'diagnostics:read', 'diagnostics:manage', 'commercial:read', 'commercial:manage',
  'audit:read', 'analytics:read', 'configuration:read', 'configuration:manage', 'billing:manage',
  'tasks:read', 'tasks:manage', 'support:read', 'support:manage',
  'membership:read', 'membership:manage',
] as const;

export type AdminPermission = typeof adminPermissionOptions[number];

export const adminPackages = [
  {
    id: 'finance',
    name: 'Finance',
    department: 'Finance',
    permissions: ['analytics:read', 'commercial:read', 'configuration:read', 'billing:manage'],
  },
  {
    id: 'hr',
    name: 'HR',
    department: 'HR',
    permissions: ['users:read', 'users:manage', 'keys:read'],
  },
  {
    id: 'marketing',
    name: 'Marketing',
    department: 'Marketing',
    permissions: ['analytics:read', 'support:read', 'configuration:read', 'billing:manage'],
  },
  {
    id: 'operations',
    name: 'Operations',
    department: 'Operations',
    permissions: ['analytics:read', 'tenants:read', 'tenants:manage', 'sessions:read', 'diagnostics:read', 'tasks:read', 'tasks:manage'],
  },
  {
    id: 'sales',
    name: 'Sales',
    department: 'Sales',
    permissions: ['analytics:read', 'commercial:read', 'membership:read', 'membership:manage', 'tenants:read'],
  },
  {
    id: 'support',
    name: 'Support',
    department: 'Support',
    permissions: ['support:read', 'support:manage', 'diagnostics:read', 'sessions:read'],
  },
  {
    id: 'engineering',
    name: 'Engineering',
    department: 'Engineering',
    permissions: ['analytics:read', 'diagnostics:read', 'diagnostics:manage', 'configuration:read'],
  },
  {
    id: 'custom',
    name: 'Custom',
    department: 'Custom',
    permissions: [],
  },
] as const satisfies readonly {
  id: string;
  name: string;
  department: string;
  permissions: readonly AdminPermission[];
}[];

const packageIds = new Set<string>(adminPackages.map((item) => item.id));

export function normalizeAdminPackages(value: unknown, department: string): string[] {
  const parsed = Array.isArray(value)
    ? value.filter((item): item is string => typeof item === 'string')
    : [];
  const valid = [...new Set(parsed)].filter((id) => packageIds.has(id));
  if (valid.length > 0) return valid;
  const legacyId = department.trim().toLowerCase().replace(/\s+/g, '-');
  return packageIds.has(legacyId) ? [legacyId] : ['custom'];
}

export function adminPackagePermissions(packages: readonly string[]): AdminPermission[] {
  const selected = new Set(packages);
  return [...new Set(
    adminPackages
      .filter((item) => selected.has(item.id))
      .flatMap((item) => item.permissions),
  )];
}

export function effectiveAdminPermissions(packages: readonly string[], stored: readonly string[]): string[] {
  return [...new Set([...adminPackagePermissions(packages), ...stored])];
}

export function isAdminPermission(value: string): value is AdminPermission {
  return (adminPermissionOptions as readonly string[]).includes(value);
}
