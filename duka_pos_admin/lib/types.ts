export type Tenant = {
  id: string;
  shopName: string;
  admin?: string | null;
  _count?: { profiles: number; sales: number };
  activeProfiles?: number;
  totalSales?: number;
  lastActivity?: string | null;
  settings?: { mpesa?: boolean; etims?: boolean; payhero?: boolean } | null;
};

export type ChurnSnapshot = {
  id: string;
  tenantId: string;
  tenant?: { id: string; shopName: string };
  risk: 'none' | 'low' | 'medium' | 'high';
  score: number;
  streakDays: number;
  daysSinceLastActive: number;
  computedAt: string;
};

export type Sale = {
  id: string;
  tenantId: string;
  tenant?: { id: string; shopName: string };
  total: number;
  profit: number;
  paymentMethod?: string | null;
  staff?: string | null;
  createdAt: string;
};

export type AppSession = {
  id: string;
  tenantId: string;
  tenant?: { id: string; shopName: string };
  device?: string | null;
  createdAt: string;
  expiresAt: string;
};

export type SupportTicket = {
  id: string;
  type: 'ticket' | 'request';
  title: string;
  description?: string | null;
  status: 'open' | 'in_progress' | 'resolved' | 'closed';
  createdAt: string;
  deviceId?: string | null;
  tenantId?: string | null;
  tenant?: { id: string; shopName: string };
};

export type AuditLog = {
  id: string;
  adminId?: string | null;
  action: string;
  targetType: string;
  targetId?: string | null;
  tenantId?: string | null;
  at: string;
};

export type DashboardStats = {
  tenants: number;
  activeUsers: number;
  sales: { count: number; total: number; profit: number };
  churnByRisk: Record<string, number>;
};

export type PageQuery = {
  from?: string;
  to?: string;
  tenantId?: string;
  limit?: number;
  status?: string;
  type?: string;
};

export type RiskColorProps = { risk: string };
