import { getD1DatabaseBinding } from './prisma';

type AdminAuditInput = {
  adminId: string;
  action: string;
  targetType: string;
  targetId?: string | null;
  tenantId?: string | null;
  onlyAfterSuccessfulWrite?: boolean;
};

type D1PreparedStatement = ReturnType<ReturnType<typeof getD1DatabaseBinding>['prepare']>;

export function prepareAdminAudit(
  input: AdminAuditInput,
  db: ReturnType<typeof getD1DatabaseBinding> = getD1DatabaseBinding(),
): D1PreparedStatement {
  return db.prepare(`
    INSERT INTO admin_audit_logs (
      id, admin_id, action, target_type, target_id, tenant_id, "at"
    )
    SELECT ?, ?, ?, ?, ?, ?, ?
    ${input.onlyAfterSuccessfulWrite ? 'WHERE changes() = 1' : ''}
  `).bind(
    globalThis.crypto.randomUUID(),
    input.adminId,
    input.action,
    input.targetType,
    input.targetId ?? null,
    input.tenantId ?? null,
    new Date().toISOString(),
  );
}
