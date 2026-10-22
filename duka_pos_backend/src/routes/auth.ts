/**
 * The verify flow: create the online account, prove the email, sign the till
 * in. Three endpoints and nothing else.
 *
 *   POST /auth/link     email + 6-digit admin PIN + shop name
 *                        -> creates the Keycloak account (disabled), emails a
 *                           6-digit code, returns where it was sent
 *   POST /auth/verify    email + 6-digit admin PIN + the 6-digit code
 *                        -> consumes the code, enables and marks the account
 *                           verified, links or creates the shop, and returns
 *                           the shop's tenant id. The CREDENTIAL is not
 *                           returned: the till signs in to Keycloak and sends
 *                           that token, and Keycloak's token is the only one
 *                           this service accepts.

 * WHY THESE ARE OUTSIDE THE AUTH MIDDLEWARE
 * Every one of them runs *before* the shop has a token: the first call has to
 * work for an account that does not exist yet, so there is nothing to
 * authenticate with. They are therefore the only authenticated-by-content
 * endpoints in the service, and they are hardened accordingly — a strict rate
 * limit per address, codes that expire, attempts that burn the code, and a
 * Keycloak account that stays dark until an emailed code is presented.
 *
 * WHAT THIS ENDPOINT REFUSES TO DO
 * It will not tell a caller whether an email has an account. Both answers
 * return the same body, so the endpoint cannot be used to enumerate which
 * addresses use SimpleSales.
 */

import { Router, Request, Response } from 'express';
import rateLimit, { ipKeyGenerator } from 'express-rate-limit';
import { randomBytes } from 'node:crypto';
import { prisma } from '../lib/prisma.js';
import { asyncHandler } from '../lib/http.js';
import {
  linkSchema,
  parseBody,
  pinResetConfirmSchema,
  pinResetRequestSchema,
  verificationCodeSchema,
} from '../lib/validation.js';
import { log } from '../lib/observability.js';
import {
  CODE_REQUEST_WINDOW_MINUTES,
  MAX_CODES_PER_WINDOW,
  VERIFICATION_TTL_MINUTES,
  attemptsRemaining,
  codeRequestWindowStart,
  generateVerificationCode,
  hashCodeSecret,
  hashesMatch,
  isVerificationExpired,
  maskEmail,
  newSalt,
} from '../lib/verification.js';
import { createKeycloakAdminClient, keycloakAdminOptionsFromEnv } from '../lib/keycloak_admin.js';
import { createEmailJsTransport, type EmailTransport } from '../lib/email_sender.js';

const router = Router();

/** How long a refresh token lives. A till is a shared device that is switched
 * on every morning; a shorter lifetime means asking the owner to re-verify
 * from a phone mailbox every few days, which is the failure this flow exists
 * to remove. Rotation, not brevity, is what limits a stolen token. */
const REFRESH_TOKEN_TTL_MS = 180 * 24 * 60 * 60 * 1000;

/** A dev-only escape hatch: without an EmailJS template there is no way to
 * read the code off a phone. It is off unless BOTH conditions hold — a
 * non-production environment and an explicit flag — and the response field is
 * ignored by the release build's clients. */
function debugCodesEnabled(): boolean {
  return process.env.NODE_ENV !== 'production' && process.env.VERIFICATION_DEBUG_CODES === 'true';
}

function verificationSecret(): string {
  return process.env.EMAIL_VERIFICATION_SECRET ?? '';
}

function identityConfigured(): boolean {
  return Boolean(verificationSecret() && keycloakAdminOptionsFromEnv(process.env));
}

function mailerConfigured(): boolean {
  return Boolean(
    process.env.EMAILJS_SERVICE_ID &&
      process.env.EMAILJS_TEMPLATE_ID &&
      process.env.EMAILJS_PUBLIC_KEY &&
      process.env.EMAILJS_PRIVATE_KEY,
  );
}

function notConfigured(res: Response, requestId?: string) {
  return res.status(503).json({
    error: 'Online account verification is not configured on this server',
    code: 'VERIFICATION_NOT_CONFIGURED',
    requestId,
  });
}

/**
 * Keyed on the address as well as the IP, so one caller cannot spend the
 * whole limit on other people's mailboxes and one shop cannot be locked out by
 * its neighbours.
 *
 * The IP goes through the library's `ipKeyGenerator`, which folds an IPv6
 * address down to its /64. A raw IPv6 address is a whole /64 of addresses, so
 * a caller with one prefix could take a fresh identity for every request and
 * walk past the limit — which is the bypass the library now refuses to start
 * without, and the reason this helper exists.
 */
function addressKey(req: Request): string {
  const body = req.body as { email?: unknown };
  const email = typeof body?.email === 'string' ? body.email.trim().toLowerCase() : '';
  return `${ipKeyGenerator(req.ip ?? 'unknown')}:${email}`;
}

const linkLimiter = rateLimit({
  windowMs: CODE_REQUEST_WINDOW_MINUTES * 60_000,
  limit: MAX_CODES_PER_WINDOW,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  keyGenerator: addressKey,
});

const verifyLimiter = rateLimit({
  windowMs: 10 * 60_000,
  limit: 20,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  keyGenerator: addressKey,
});

/**
 * The reset request gets its OWN budget.
 *
 * Sharing the link limiter looked tidy — one budget per address — but it made
 * two unrelated actions spend each other's: an owner who had just tried to
 * link a shop could be told to wait fifteen minutes before asking for a reset
 * code, and the reset is the flow somebody reaches for when the till is stuck.
 * Same shape, separate counter.
 */
const pinResetLimiter = rateLimit({
  windowMs: CODE_REQUEST_WINDOW_MINUTES * 60_000,
  limit: MAX_CODES_PER_WINDOW,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  keyGenerator: addressKey,
});

function buildMailer(): EmailTransport {
  const transport = createEmailJsTransport({
    serviceId: process.env.EMAILJS_SERVICE_ID ?? '',
    templateId: process.env.EMAILJS_TEMPLATE_ID ?? '',
    publicKey: process.env.EMAILJS_PUBLIC_KEY ?? '',
    privateKey: process.env.EMAILJS_PRIVATE_KEY ?? '',
    appName: process.env.APP_NAME ?? 'SimpleSales',
  });
  return transport.send;
}

type LinkedShop = {
  tenantId: string;
  shopName: string;
  profileId: string;
  created: boolean;
};

/**
 * The shop this email owns, adopting or creating one if it can.
 *
 * The order matters and is deliberately the same order `/tenant/provision`
 * uses, so an account that links through this flow and one that links through
 * the browser flow end up attached to the same tenant:
 *
 *  1. This exact account, this exact shop name — the retry path. A link that
 *     failed after the tenant was written is not a second tenant.
 *  2. This account, any shop — the oldest one, because that is the shop the
 *     owner set up first and the one they mean when they say "my shop".
 *  3. An unclaimed row with this email — a profile created before accounts
 *     were linked, adopted rather than duplicated.
 *  4. Nothing at all, and [allowCreate] — a new tenant, with the owner as its
 *     admin. Without details to name it, there is nothing to create, and the
 *     caller is told that rather than being handed a shop called "My shop".
 */
async function ensureOwnerProfile(
  input: { oidcSubject: string; email: string; shopName?: string; ownerName?: string },
  options: { allowCreate: boolean },
): Promise<LinkedShop | null> {
  const exact = await prisma.profile.findFirst({
    where: { oidcSubject: input.oidcSubject, tenant: { shopName: input.shopName?.trim() } },
    include: { tenant: true },
  });
  if (exact) {
    return { tenantId: exact.tenantId, shopName: exact.tenant.shopName, profileId: exact.id, created: false };
  }

  const owned = await prisma.profile.findFirst({
    where: { oidcSubject: input.oidcSubject, active: true, deletedAt: null },
    include: { tenant: true },
    orderBy: { createdAt: 'asc' },
  });
  if (owned) {
    return { tenantId: owned.tenantId, shopName: owned.tenant.shopName, profileId: owned.id, created: false };
  }

  const unclaimed = await prisma.profile.findFirst({
    where: { email: input.email, oidcSubject: null, active: true, deletedAt: null },
    include: { tenant: true },
  });
  if (unclaimed) {
    const adopted = await prisma.profile.update({
      where: { id: unclaimed.id },
      data: { oidcSubject: input.oidcSubject, email: input.email },
    });
    return {
      tenantId: unclaimed.tenantId,
      shopName: unclaimed.tenant.shopName,
      profileId: adopted.id,
      created: false,
    };
  }

  if (!options.allowCreate || !input.shopName?.trim() || !input.ownerName?.trim()) return null;

  const created = await prisma.$transaction(async (tx) => {
    const tenant = await tx.tenant.create({ data: { shopName: input.shopName!.trim() } });
    const profile = await tx.profile.create({
      data: {
        oidcSubject: input.oidcSubject,
        tenantId: tenant.id,
        name: input.ownerName!.trim(),
        email: input.email,
        role: 'admin',
      },
    });
    return { tenant, profile };
  });
  return { tenantId: created.tenant.id, shopName: created.tenant.shopName, profileId: created.profile.id, created: true };
}

router.post('/link', linkLimiter, asyncHandler(async (req: Request, res: Response) => {
    const requestId = req.requestId;
    const { email, pin, shopName, ownerName } = parseBody(linkSchema, req.body);

    if (!identityConfigured() || (!mailerConfigured() && !debugCodesEnabled())) {
      return notConfigured(res, requestId);
    }

    const keycloakOptions = keycloakAdminOptionsFromEnv(process.env)!;
    const keycloak = createKeycloakAdminClient({ ...keycloakOptions });
    const secret = verificationSecret();

    // The second, database-side limit. The IP limiter above is per address;
    // this one is per mailbox, and it counts codes that were already sent —
    // including consumed ones — so a caller cannot reset it by using them.
    const recent = await prisma.emailVerification.count({
      where: { email, createdAt: { gte: codeRequestWindowStart(new Date()) } },
    });
    if (recent >= MAX_CODES_PER_WINDOW) {
      log('warn', 'auth.code_rate_limited', { requestId, email: maskEmail(email) });
      return res.status(429).json({
        error: `Too many codes requested. Wait ${CODE_REQUEST_WINDOW_MINUTES} minutes and try again.`,
        code: 'TOO_MANY_CODES',
        requestId,
      });
    }

    let user;
    try {
      // The password IS the owner's 6-digit admin PIN — the one secret they
      // already keep for the till. It is set here and never stored here:
      // Keycloak keeps a hash, and the server's copy of the PIN is the hash
      // it already binds into the challenge.
      user = await keycloak.ensureUser(email, pin);
    } catch (error) {
      log('error', 'auth.keycloak_unreachable', { requestId, message: error instanceof Error ? error.message : 'unknown' });
      return res.status(502).json({ error: 'Could not reach the identity server', code: 'IDENTITY_UNAVAILABLE', requestId });
    }

    // One live code at a time. Consuming the outstanding ones is what makes
    // the newest email the only one that works, and it is why a "resend"
    // cannot leave two valid codes in a mailbox.
    await prisma.emailVerification.updateMany({
      where: { email, consumedAt: null },
      data: { consumedAt: new Date() },
    });

    const code = generateVerificationCode();
    const salt = newSalt();
    const challenge = await prisma.emailVerification.create({
      data: {
        email,
        subject: user.id,
        salt,
        codeHash: hashCodeSecret(code, salt, secret),
        pinHash: hashCodeSecret(pin, salt, secret),
        expiresAt: new Date(Date.now() + VERIFICATION_TTL_MINUTES * 60_000),
      },
    });

    try {
      if (mailerConfigured()) {
        await buildMailer()({ to: email, code, shopName, ttlMinutes: VERIFICATION_TTL_MINUTES });
      }
    } catch (error) {
      // The code exists but nobody received it. Burning the challenge is the
      // difference between "try again" and a shop waiting for an email that
      // was never going to arrive.
      await prisma.emailVerification.update({ where: { id: challenge.id }, data: { consumedAt: new Date() } });
      log('error', 'auth.email_failed', { requestId, message: error instanceof Error ? error.message : 'unknown' });
      return res.status(502).json({ error: 'The verification email could not be sent', code: 'EMAIL_UNAVAILABLE', requestId });
    }

    // The code, the PIN and the hash are all absent from this line: a log is
    // read by more people than the phone is.
    log('info', 'auth.code_sent', { requestId, email: maskEmail(email), subject: user.id, accountCreated: user.created, shopName });

    res.json({
      status: 'code_sent',
      challenge_id: challenge.id,
      // Masked, because the caller already knows the address and nobody else
      // is entitled to it — and so this endpoint cannot enumerate accounts.
      email: maskEmail(email),
      expires_in_seconds: VERIFICATION_TTL_MINUTES * 60,
      ...(debugCodesEnabled() ? { debug_code: code } : {}),
    });
}));

router.post('/verify', verifyLimiter, asyncHandler(async (req: Request, res: Response) => {
    const requestId = req.requestId;
    const { email, pin, code, shopName, ownerName } = parseBody(verificationCodeSchema, req.body);

    if (!identityConfigured()) {
      return notConfigured(res, requestId);
    }

    const secret = verificationSecret();
    const now = new Date();

    const challenge = await prisma.emailVerification.findFirst({
      where: { email, consumedAt: null },
      orderBy: { createdAt: 'desc' },
    });

    if (!challenge) {
      return res.status(400).json({ error: 'That code has expired. Ask for a new one.', code: 'VERIFICATION_EXPIRED', requestId });
    }
    if (isVerificationExpired(challenge.expiresAt, now)) {
      await prisma.emailVerification.update({ where: { id: challenge.id }, data: { consumedAt: now } });
      return res.status(400).json({ error: 'That code has expired. Ask for a new one.', code: 'VERIFICATION_EXPIRED', requestId });
    }
    if (attemptsRemaining(challenge.attempts) <= 0) {
      await prisma.emailVerification.update({ where: { id: challenge.id }, data: { consumedAt: now } });
      log('warn', 'auth.code_burnt', { requestId, email: maskEmail(email) });
      return res.status(429).json({ error: 'Too many wrong attempts. Ask for a new code.', code: 'TOO_MANY_ATTEMPTS', requestId });
    }

    // Both factors, both through the same constant-time comparison. A wrong
    // PIN and a wrong code give the same answer, so neither can be learned
    // one at a time.
    const codeCorrect = hashesMatch(hashCodeSecret(code, challenge.salt, secret), challenge.codeHash);
    const pinCorrect = hashesMatch(hashCodeSecret(pin, challenge.salt, secret), challenge.pinHash);
    if (!codeCorrect || !pinCorrect) {
      const updated = await prisma.emailVerification.update({
        where: { id: challenge.id },
        data: { attempts: { increment: 1 } },
      });
      log('warn', 'auth.code_rejected', { requestId, email: maskEmail(email), attemptsRemaining: attemptsRemaining(updated.attempts) });
      return res.status(400).json({
        error: 'That code is not right.',
        code: 'VERIFICATION_INVALID',
        attempts_remaining: attemptsRemaining(updated.attempts),
        requestId,
      });
    }

    // Single use: consuming every outstanding code for the address means a
    // verified shop cannot be re-verified with an older email.
    await prisma.emailVerification.updateMany({ where: { email, consumedAt: null }, data: { consumedAt: now } });

    const keycloakOptions = keycloakAdminOptionsFromEnv(process.env)!;
    const keycloak = createKeycloakAdminClient({ ...keycloakOptions });
    try {
      await keycloak.activateUser(challenge.subject);
    } catch (error) {
      log('error', 'auth.activate_failed', { requestId, message: error instanceof Error ? error.message : 'unknown' });
      return res.status(502).json({ error: 'Could not reach the identity server', code: 'IDENTITY_UNAVAILABLE', requestId });
    }

    const shop = await ensureOwnerProfile(
      { oidcSubject: challenge.subject, email, shopName, ownerName },
      { allowCreate: true },
    );
    if (!shop) {
      // An account with no shop and no details to build one from. The till
      // always sends both from its own setup screen, so this is a caller that
      // never set a shop up — which is a setup problem, not a verification one.
      return res.status(400).json({
        error: 'This account has no shop yet. Finish shop setup on the till and try again.',
        code: 'SHOP_SETUP_REQUIRED',
        requestId,
      });
    }

    await prisma.profile.update({
      where: { id: shop.profileId },
      data: { emailVerifiedAt: now },
    });

    log('info', 'auth.verified', {
      requestId,
      email: maskEmail(email),
      tenantId: shop.tenantId,
      shopCreated: shop.created,
    });

    res.json({
      status: 'verified',
      tenant_id: shop.tenantId,
      shop_name: shop.shopName,
      role: 'admin',
      // NO TOKEN. The account is live in Keycloak now, and the till signs in
      // to Keycloak and sends THAT token. This service accepts nothing else.
      // The next step is the identity server's, and it is the one that knows
      // the password.
      sign_in_required: true,
    });
}));

// ---------------------------------------------------------------- PIN reset

/**
 * Step one of Forgot PIN: email a code to the address on the account.
 *
 * ## WHY THIS DOES NOT NEED THE OLD PIN
 *
 * Every other auth endpoint here needs the admin PIN. This one cannot: the
 * owner asking is the owner who forgot it. The proof is possession of the
 * verified mailbox, which is the same proof /link uses.
 *
 * ## WHY IT NEVER SAYS "NO SUCH ACCOUNT"
 *
 * The answer is the same whether or not the address has an account. A reset
 * form that answers "that email is not registered" is an oracle for which
 * addresses shop with this service, and that is exactly what /link refuses to
 * be. An address with no account gets a challenge that no code can satisfy,
 * and the person trying sees the same "check your email" screen.
 */
router.post('/pin-reset/request', pinResetLimiter, asyncHandler(async (req: Request, res: Response) => {
  const requestId = req.requestId;
  const { email } = parseBody(pinResetRequestSchema, req.body);

  if (!identityConfigured() || (!mailerConfigured() && !debugCodesEnabled())) {
    return notConfigured(res, requestId);
  }

  // The same per-mailbox ceiling /link enforces, counting sent codes so it
  // cannot be reset by spending them.
  const recent = await prisma.emailVerification.count({
    where: { email, createdAt: { gte: codeRequestWindowStart(new Date()) } },
  });
  if (recent >= MAX_CODES_PER_WINDOW) {
    log('warn', 'auth.pin_reset_rate_limited', { requestId, email: maskEmail(email) });
    return res.status(429).json({
      error: `Too many codes requested. Wait ${CODE_REQUEST_WINDOW_MINUTES} minutes and try again.`,
      code: 'TOO_MANY_CODES',
      requestId,
    });
  }

  const keycloak = createKeycloakAdminClient({ ...keycloakAdminOptionsFromEnv(process.env)! });
  const secret = verificationSecret();

  let subject = '';
  try {
    const user = await keycloak.findUserByEmail(email);
    subject = user?.id ?? '';
  } catch (error) {
    log('error', 'auth.keycloak_unreachable', {
      requestId,
      message: error instanceof Error ? error.message : 'unknown',
    });
    return res.status(502).json({
      error: 'Could not reach the identity server',
      code: 'IDENTITY_UNAVAILABLE',
      requestId,
    });
  }

  // One live code at a time, exactly as /link does.
  await prisma.emailVerification.updateMany({
    where: { email, consumedAt: null },
    data: { consumedAt: new Date() },
  });

  const code = generateVerificationCode();
  const salt = newSalt();
  const challenge = await prisma.emailVerification.create({
    data: {
      email,
      // Empty when there is no account: the confirm step refuses to set a
      // password for nobody.
      subject,
      salt,
      codeHash: hashCodeSecret(code, salt, secret),
      // A reset is the flow where the PIN is NOT known, so there is nothing to
      // bind. Random bytes keep the column meaningful and make it impossible
      // for anything the owner types to match on this path.
      pinHash: hashCodeSecret(randomBytes(16).toString('hex'), salt, secret),
      expiresAt: new Date(Date.now() + VERIFICATION_TTL_MINUTES * 60_000),
    },
  });

  if (subject && mailerConfigured()) {
    // The email names the shop, so the owner recognises which till is asking
    // even when they run more than one. The address proves the account; the
    // shop name is only there to make the message readable.
    const profile = await prisma.profile.findFirst({
      where: { oidcSubject: subject, deletedAt: null },
      include: { tenant: true },
      orderBy: { createdAt: 'asc' },
    });
    try {
      await buildMailer()({
        to: email,
        code,
        shopName: profile?.tenant.shopName ?? process.env.APP_NAME ?? 'SimpleSales',
        ttlMinutes: VERIFICATION_TTL_MINUTES,
      });
    } catch (error) {
      await prisma.emailVerification.update({
        where: { id: challenge.id },
        data: { consumedAt: new Date() },
      });
      log('error', 'auth.email_failed', {
        requestId,
        message: error instanceof Error ? error.message : 'unknown',
      });
      return res.status(502).json({
        error: 'The verification email could not be sent',
        code: 'EMAIL_UNAVAILABLE',
        requestId,
      });
    }
  }

  log('info', 'auth.pin_reset_code_sent', {
    requestId,
    email: maskEmail(email),
    accountFound: Boolean(subject),
  });

  res.json({
    status: 'code_sent',
    // The field name the till reads. Snake_case matches the rest of this
    // service's responses; `challengeId` is accepted by the client's own
    // reader for the older spelling.
    challengeId: challenge.id,
    challenge_id: challenge.id,
    email: maskEmail(email),
    expires_in_seconds: VERIFICATION_TTL_MINUTES * 60,
    ...(debugCodesEnabled() && subject ? { debug_code: code } : {}),
  });
}));

/**
 * Step two of Forgot PIN: spend the code and set the new PIN.
 *
 * ## THE NEW PIN IS ALSO THE KEYCLOAK PASSWORD
 *
 * The admin PIN is the account's password (see the file header). A reset that
 * changed only the phone's copy would leave the identity server expecting the
 * PIN the owner has forgotten, so the next cloud sign-in — and the receipt
 * that depends on it — would fail with the credential the app had just told
 * them to use. Both copies move together, here.
 *
 * ## WHAT FAILURE LOOKS LIKE
 *
 * A wrong code burns one attempt and answers 400, the same shape /verify uses.
 * An unknown challenge answers 400 too, never 404: the till reads 404 as "that
 * email has no account", and this endpoint is not an enumeration oracle.
 */
router.post('/pin-reset/confirm', verifyLimiter, asyncHandler(async (req: Request, res: Response) => {
  const requestId = req.requestId;
  const { email, challengeId, code, newPin } = parseBody(pinResetConfirmSchema, req.body);

  if (!identityConfigured()) {
    return notConfigured(res, requestId);
  }

  const secret = verificationSecret();
  const now = new Date();

  const challenge = await prisma.emailVerification.findUnique({ where: { id: challengeId } });
  if (!challenge || challenge.email !== email) {
    return res.status(400).json({
      error: 'That code has expired. Ask for a new one.',
      code: 'RESET_EXPIRED',
      requestId,
    });
  }
  if (challenge.consumedAt) {
    return res.status(400).json({
      error: 'That code has already been used. Ask for a new one.',
      code: 'RESET_SPENT',
      requestId,
    });
  }
  if (isVerificationExpired(challenge.expiresAt, now)) {
    await prisma.emailVerification.update({ where: { id: challenge.id }, data: { consumedAt: now } });
    return res.status(400).json({
      error: 'That code has expired. Ask for a new one.',
      code: 'RESET_EXPIRED',
      requestId,
    });
  }
  if (attemptsRemaining(challenge.attempts) <= 0) {
    await prisma.emailVerification.update({ where: { id: challenge.id }, data: { consumedAt: now } });
    log('warn', 'auth.pin_reset_burnt', { requestId, email: maskEmail(email) });
    return res.status(429).json({
      error: 'Too many wrong attempts. Ask for a new code.',
      code: 'TOO_MANY_ATTEMPTS',
      requestId,
    });
  }

  const codeCorrect = hashesMatch(
    hashCodeSecret(code, challenge.salt, secret),
    challenge.codeHash,
  );
  if (!codeCorrect) {
    const updated = await prisma.emailVerification.update({
      where: { id: challenge.id },
      data: { attempts: { increment: 1 } },
    });
    log('warn', 'auth.pin_reset_rejected', {
      requestId,
      email: maskEmail(email),
      attemptsRemaining: attemptsRemaining(updated.attempts),
    });
    return res.status(400).json({
      error: 'That code is not right.',
      code: 'RESET_INVALID',
      attempts_remaining: attemptsRemaining(updated.attempts),
      requestId,
    });
  }

  if (!challenge.subject) {
    // The code was right but there was never an account to reset. It cannot
    // happen through the mailbox, but it can through a fabricated challenge.
    return res.status(400).json({
      error: 'That code is not right.',
      code: 'RESET_INVALID',
      requestId,
    });
  }

  // Spent before the password moves: a retry must not get a second chance to
  // set a different PIN from the same code.
  await prisma.emailVerification.updateMany({
    where: { email, consumedAt: null },
    data: { consumedAt: now },
  });

  const keycloak = createKeycloakAdminClient({ ...keycloakAdminOptionsFromEnv(process.env)! });
  try {
    await keycloak.setPassword(challenge.subject, newPin);
  } catch (error) {
    log('error', 'auth.pin_reset_keycloak_failed', {
      requestId,
      message: error instanceof Error ? error.message : 'unknown',
    });
    return res.status(502).json({
      error: 'Could not reach the identity server',
      code: 'IDENTITY_UNAVAILABLE',
      requestId,
    });
  }

  log('info', 'auth.pin_reset', { requestId, email: maskEmail(email) });
  res.json({ status: 'reset' });
}));

export default router;
