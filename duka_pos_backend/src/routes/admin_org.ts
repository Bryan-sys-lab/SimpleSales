import { Request, Response, Router } from 'express';
import { z } from 'zod';
import { asyncHandler } from '../lib/http';
import { parseBody } from '../lib/validation';
import { getD1DatabaseBinding, prisma } from '../lib/prisma';
import { prepareAdminAudit } from '../lib/admin_audit_d1';
import { systemAdminMiddleware } from '../middleware/auth';

const router = Router();
router.use(systemAdminMiddleware);

async function adminDescendants(keyId: string, department: string): Promise<string[]> {
  let frontier = [keyId]; const ids: string[] = [];
  for (let depth = 0; depth < 4 && frontier.length; depth += 1) {
    const children = await prisma.adminKey.findMany({ where: { parentKeyId: { in: frontier }, department }, select: { id: true } });
    frontier = children.map((child) => child.id); ids.push(...frontier);
  }
  return ids;
}
async function isReportOf(keyId: string, target: { parentKeyId: string | null; department: string }, department: string): Promise<boolean> {
  if (target.department !== department) return false;
  let parentId = target.parentKeyId;
  for (let depth = 0; depth < 5 && parentId; depth += 1) {
    if (parentId === keyId) return true;
    const parent = await prisma.adminKey.findUnique({ where: { id: parentId }, select: { parentKeyId: true, department: true } });
    if (!parent || parent.department !== department) return false;
    parentId = parent.parentKeyId;
  }
  return false;
}

const createTaskSchema = z.object({
  title: z.string().trim().min(3).max(160),
  description: z.string().trim().max(4000).optional().nullable(),
  assigneeKeyId: z.string().trim().min(1).max(80),
  dueAt: z.string().datetime().optional().nullable(),
}).strict();
const updateTaskSchema = z.object({ status: z.enum(['in_progress', 'blocked', 'done', 'cancelled']) }).strict();

router.get('/tasks', asyncHandler(async (req: Request, res: Response) => {
  const access = (req as any).adminAccess;
  const reports = access.isSuperAdmin ? [] : await adminDescendants(access.keyId, access.department);
  const where = access.isSuperAdmin ? {} : { assigneeKeyId: { in: [access.keyId, ...reports] } };
  const tasks = await prisma.adminTask.findMany({ where, include: { assignee: { select: { id: true, email: true, department: true, role: true, parentKeyId: true } } }, orderBy: [{ status: 'asc' }, { createdAt: 'desc' }], take: 500 });
  res.json({ tasks });
}));

router.post('/tasks', asyncHandler(async (req: Request, res: Response) => {
  const input = parseBody(createTaskSchema, req.body);
  const access = (req as any).adminAccess;
  const assignee = await prisma.adminKey.findUnique({ where: { id: input.assigneeKeyId } });
  if (!assignee || assignee.revokedAt || assignee.expiresAt <= new Date()) return res.status(404).json({ error: 'Active assignee not found' });
  if (!access.isSuperAdmin && (!access.canAssignTasks || assignee.parentKeyId !== access.keyId || assignee.department !== access.department)) {
    return res.status(403).json({ error: 'Tasks can only be assigned to your active direct reports' });
  }
  const taskId = crypto.randomUUID();
  const now = new Date();
  const db = getD1DatabaseBinding();
  const results = await db.batch([
    db.prepare(`
      INSERT INTO admin_tasks (
        id, title, description, department, status, created_by,
        assignee_key_id, due_at, created_at, updated_at
      ) VALUES (?, ?, ?, ?, 'assigned', ?, ?, ?, ?, ?)
    `).bind(
      taskId,
      input.title,
      input.description ?? null,
      assignee.department,
      req.auth?.sub ?? 'unknown',
      assignee.id,
      input.dueAt ? new Date(input.dueAt).toISOString() : null,
      now.toISOString(),
      now.toISOString(),
    ),
    prepareAdminAudit({
      adminId: req.auth?.sub ?? 'unknown',
      action: 'admin_task_assigned',
      targetType: 'admin_task',
      targetId: taskId,
      onlyAfterSuccessfulWrite: true,
    }, db),
  ]);
  if ((results[0]?.meta.changes ?? 0) !== 1) throw new Error('Administrator task could not be created');
  const task = {
    id: taskId,
    title: input.title,
    description: input.description ?? null,
    department: assignee.department,
    status: 'assigned',
    createdBy: req.auth?.sub ?? 'unknown',
    assigneeKeyId: assignee.id,
    dueAt: input.dueAt ? new Date(input.dueAt) : null,
    createdAt: now,
    updatedAt: now,
    assignee: {
      id: assignee.id,
      email: assignee.email,
      department: assignee.department,
      role: assignee.role,
      parentKeyId: assignee.parentKeyId,
    },
  };
  res.status(201).json({ task });
}));

router.patch('/tasks/:taskId', asyncHandler(async (req: Request, res: Response) => {
  const { status } = parseBody(updateTaskSchema, req.body);
  const task = await prisma.adminTask.findUnique({ where: { id: req.params.taskId as string }, include: { assignee: true } });
  if (!task) return res.status(404).json({ error: 'Task not found' });
  const access = (req as any).adminAccess;
  const isAssignee = access.keyId === task.assigneeKeyId;
  const managesAssignee = !access.isSuperAdmin && await isReportOf(access.keyId, task.assignee, access.department);
  if (!access.isSuperAdmin && !isAssignee && !managesAssignee) return res.status(403).json({ error: 'Task is outside your reporting line' });
  const db = getD1DatabaseBinding();
  const results = await db.batch([
    db.prepare('UPDATE admin_tasks SET status = ?, updated_at = ? WHERE id = ?')
      .bind(status, new Date().toISOString(), task.id),
    prepareAdminAudit({
      adminId: req.auth?.sub ?? 'unknown',
      action: 'admin_task_status_updated',
      targetType: 'admin_task',
      targetId: task.id,
      onlyAfterSuccessfulWrite: true,
    }, db),
  ]);
  if ((results[0]?.meta.changes ?? 0) !== 1) throw new Error('Administrator task could not be updated');
  const updated = await prisma.adminTask.findUnique({
    where: { id: task.id },
    include: { assignee: { select: { id: true, email: true, department: true, role: true, parentKeyId: true } } },
  });
  if (!updated) throw new Error('Updated administrator task could not be reloaded');
  res.json({ task: updated });
}));

router.get('/reports', asyncHandler(async (req: Request, res: Response) => {
  const access = (req as any).adminAccess;
  const where = access.isSuperAdmin ? {} : { department: access.department, parentKeyId: access.keyId };
  const reports = await prisma.adminKey.findMany({ where, select: { id: true, email: true, phone: true, department: true, role: true, permissions: true, canRecruit: true, canMintKeys: true, canAssignTasks: true, createdBy: true, createdAt: true, usedAt: true, expiresAt: true, revokedAt: true, parentKeyId: true }, orderBy: { createdAt: 'desc' }, take: 500 });
  res.json({ reports });
}));

export default router;
