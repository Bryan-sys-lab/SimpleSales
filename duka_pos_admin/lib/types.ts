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

export type TaxEntityAdmin = {
  id: string;
  display_label: string;
  legal_form: string;
  status: string;
  linked_shop_count: number;
};

export type TaxRuleAdmin = {
  id: string;
  tax_entity_id: string;
  tax_entity?: TaxEntityAdmin | null;
  tax_type: string;
  scope: string;
  jurisdiction: string;
  rate_basis_points?: number | null;
  tax_base: string;
  filing_frequency: string;
  filing_due_day?: number | null;
  threshold_minor?: number | null;
  effective_from: string;
  effective_to?: string | null;
  source_url: string;
  source_reference?: string | null;
  reviewed_at?: string | null;
  approved_by?: string | null;
  approval_note?: string | null;
  status: string;
};

export type TaxComplianceReturn = {
  id: string;
  tax_type: 'vat' | 'tot';
  tax_entity: { id: string; displayLabel: string; legalForm: string };
  period_start: string;
  period_end: string;
  output_vat?: number;
  eligible_input_vat?: number;
  adjustments?: number;
  net_payable?: number;
  gross_sales?: number;
  estimate?: number;
  rate_basis_points?: number | null;
  evidence: Record<string, unknown>;
  status: string;
  rejection_reason?: string | null;
  status_events?: Array<{ fromStatus?: string | null; toStatus: string; actorId: string; createdAt: string }>;
  updated_at: string;
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

export type LaybyAdmin = {
  remoteId: string;
  localId: number;
  uuid: string;
  customerUuid: string;
  status: 'open' | 'completed' | 'cancelled' | 'expired';
  totalMinor: number;
  paidMinor: number;
  dueAt: string;
  createdAt: string;
  staffName: string;
  items: Array<{ productName: string; variantName?: string; qty: number; totalMinor: number }>;
  payments: Array<{ amountMinor: number; direction: 'in' | 'out'; method: string }>;
  tenant?: { id: string; shopName: string; businessProfile: string };
};

export type ExchangeAdmin = {
  remoteId: string;
  localId: number;
  uuid: string;
  originalSaleLocalId: number;
  returnLocalId: number;
  replacementSaleLocalId: number;
  status: 'completed';
  returnedTotalMinor: number;
  replacementTotalMinor: number;
  differenceMinor: number;
  differenceDirection: 'customer_pays' | 'customer_receives' | 'even';
  reason: string;
  staffName: string;
  createdAt: string;
  tenant?: { id: string; shopName: string; businessProfile: string };
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
