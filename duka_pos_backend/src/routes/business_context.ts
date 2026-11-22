import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler, requireUser } from '../lib/http';
import { parseBody } from '../lib/validation';
import { prisma } from '../lib/prisma';
import { KESIC_REFERENCE_VERSION, KESIC_VERIFIED_CODES } from '../data/kesic_codes';

const router = Router();
const roleValues = ['producer', 'manufacturer', 'importer', 'distributor', 'wholesaler', 'retailer', 'service_provider', 'mixed', 'other'] as const;
const channelValues = ['physical_shop', 'market_stall', 'mobile_route', 'online_store', 'social_commerce', 'wholesale', 'delivery', 'other'] as const;
const provenanceValues = ['owner_confirmed', 'staff_entered', 'imported', 'system_derived', 'admin_reviewed'] as const;
const provenanceKeys = new Set(['app_profile', 'primary_activity_code', 'primary_activity_status', 'secondary_activity_codes', 'operator_roles', 'sales_channels', 'county_code', 'settlement_context']);
const inputSchema = z.object({
  primaryActivityCode: z.string().trim().regex(/^\d{2,6}$/).nullable(),
  primaryActivityStatus: z.enum(['selected', 'pending', 'prefer_not_to_say']),
  activityScheme: z.literal('KESIC').nullable(),
  activityVersion: z.string().trim().min(1).max(80).nullable(),
  secondaryActivityCodes: z.array(z.string().regex(/^\d{2,6}$/)).max(4),
  operatorRoles: z.array(z.enum(roleValues)).max(roleValues.length),
  salesChannels: z.array(z.enum(channelValues)).max(channelValues.length),
  countyCode: z.string().regex(/^0(0[1-9]|[1-3][0-9]|4[0-7])$/).nullable(),
  settlementContext: z.enum(['urban', 'peri_urban', 'rural', 'unknown', 'prefer_not_to_say']),
  fieldProvenance: z.record(z.string(), z.enum(provenanceValues)),
  confirmedAt: z.string().datetime({ offset: true }).nullable(),
  schemaVersion: z.number().int().positive().max(10),
}).strict().superRefine((value, ctx) => {
  if (new Set(value.secondaryActivityCodes).size !== value.secondaryActivityCodes.length || value.secondaryActivityCodes.includes(value.primaryActivityCode ?? '')) {
    ctx.addIssue({ code: 'custom', path: ['secondaryActivityCodes'], message: 'Activity codes must be distinct.' });
  }
  if (value.primaryActivityStatus === 'selected' && (!value.primaryActivityCode || !value.activityScheme || !value.activityVersion)) {
    ctx.addIssue({ code: 'custom', path: ['primaryActivityCode'], message: 'Selected activities require code, scheme and reference version.' });
  }
  if (value.primaryActivityCode && (!value.activityScheme || !value.activityVersion)) {
    ctx.addIssue({ code: 'custom', path: ['activityVersion'], message: 'A retained activity code requires its scheme and reference version.' });
  }
  if (value.primaryActivityStatus === 'prefer_not_to_say' && value.primaryActivityCode) {
    ctx.addIssue({ code: 'custom', path: ['primaryActivityCode'], message: 'A declined activity cannot include a code.' });
  }
  if (value.primaryActivityStatus === 'selected' && value.primaryActivityCode && !KESIC_VERIFIED_CODES.has(value.primaryActivityCode)) {
    ctx.addIssue({ code: 'custom', path: ['primaryActivityCode'], message: 'Unlisted KeSIC codes must remain pending review.' });
  }
  if (value.primaryActivityStatus === 'selected' && value.activityVersion !== KESIC_REFERENCE_VERSION) {
    ctx.addIssue({ code: 'custom', path: ['activityVersion'], message: 'Selected activities must use the deployed reference version.' });
  }
  if (value.secondaryActivityCodes.some((code) => !KESIC_VERIFIED_CODES.has(code))) {
    ctx.addIssue({ code: 'custom', path: ['secondaryActivityCodes'], message: 'Secondary activities must be in the deployed verified reference.' });
  }
  const requiredProvenance = [
    'primary_activity_status',
    ...(value.primaryActivityCode ? ['primary_activity_code'] : []),
    ...(value.secondaryActivityCodes.length ? ['secondary_activity_codes'] : []),
    ...(value.operatorRoles.length ? ['operator_roles'] : []),
    ...(value.salesChannels.length ? ['sales_channels'] : []),
    ...(value.countyCode ? ['county_code'] : []),
    ...(value.settlementContext !== 'unknown' ? ['settlement_context'] : []),
  ];
  if (requiredProvenance.some((key) => !value.fieldProvenance[key]) ||
      Object.keys(value.fieldProvenance).some((key) => !provenanceKeys.has(key))) {
    ctx.addIssue({ code: 'custom', path: ['fieldProvenance'], message: 'Every supplied business detail requires field-level provenance.' });
  }
});

router.get('/', asyncHandler(async (req, res) => {
  const user = requireUser(req);
  if (user.role !== 'admin') return res.status(403).json({ error: 'Shop owner access required' });
  const record = await prisma.businessContext.findUnique({ where: { tenantId: user.tenantId } });
  const tenant = await prisma.tenant.findUnique({ where: { id: user.tenantId }, select: { businessProfile: true } });
  if (!tenant) return res.status(404).json({ error: 'Shop not found' });
  return res.json({ context: record ? { ...record, appProfile: tenant.businessProfile } : null, appProfile: tenant.businessProfile });
}));

router.put('/', asyncHandler(async (req, res) => {
  const user = requireUser(req);
  if (user.role !== 'admin') return res.status(403).json({ error: 'Shop owner access required' });
  const input = parseBody(inputSchema, req.body);
  const tenant = await prisma.tenant.findUnique({ where: { id: user.tenantId }, select: { businessProfile: true } });
  if (!tenant) return res.status(404).json({ error: 'Shop not found' });
  const context = await prisma.businessContext.upsert({
    where: { tenantId: user.tenantId },
    create: {
      tenantId: user.tenantId,
      appProfile: tenant.businessProfile,
      primaryActivityCode: input.primaryActivityCode,
      primaryActivityStatus: input.primaryActivityStatus,
      activityScheme: input.activityScheme,
      activityVersion: input.activityVersion,
      secondaryActivityCodes: input.secondaryActivityCodes,
      operatorRoles: input.operatorRoles,
      salesChannels: input.salesChannels,
      countyCode: input.countyCode,
      settlementContext: input.settlementContext,
      fieldProvenance: { ...input.fieldProvenance, app_profile: 'system_derived' },
      confirmedAt: input.confirmedAt ? new Date(input.confirmedAt) : null,
      schemaVersion: input.schemaVersion,
    },
    update: {
      appProfile: tenant.businessProfile,
      primaryActivityCode: input.primaryActivityCode,
      primaryActivityStatus: input.primaryActivityStatus,
      activityScheme: input.activityScheme,
      activityVersion: input.activityVersion,
      secondaryActivityCodes: input.secondaryActivityCodes,
      operatorRoles: input.operatorRoles,
      salesChannels: input.salesChannels,
      countyCode: input.countyCode,
      settlementContext: input.settlementContext,
      fieldProvenance: { ...input.fieldProvenance, app_profile: 'system_derived' },
      confirmedAt: input.confirmedAt ? new Date(input.confirmedAt) : null,
      schemaVersion: input.schemaVersion,
    },
  });
  return res.json({ context: { ...context, appProfile: tenant.businessProfile } });
}));

export default router;
