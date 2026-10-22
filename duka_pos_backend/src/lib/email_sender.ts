/**
 * Verification email, sent through EmailJS.
 *
 * WHY EMAILJS AND WHY SERVER-SIDE
 * The alternative was shipping an SMTP password (or an EmailJS keypair) inside
 * the APK. Anything in an APK is public: an attacker extracts it, sends a
 * thousand codes to a mailbox they chose, and the shop's domain is
 * rate-limited into the ground by a provider who blames the shop. Keys
 * therefore live only in this process, and the app asks the server to send the
 * mail rather than sending it itself.
 *
 * EmailJS is a convenience the operator opts into: without the keys the flow
 * reports that email is not configured rather than pretending a code was sent.
 * Swapping in SES or Postmark means writing one more transport with the same
 * shape and nothing else in the flow changes.
 */

export type VerificationEmail = {
  to: string;
  code: string;
  shopName: string;
  ttlMinutes: number;
};

export type EmailTransport = (message: VerificationEmail) => Promise<void>;

export type EmailJsOptions = {
  serviceId: string;
  templateId: string;
  /** EmailJS public key — the half that is safe to ship. */
  publicKey: string;
  /** EmailJS private key — the half that is not. Never leaves the server. */
  privateKey: string;
  appName?: string;
  endpoint?: string;
  /** Injectable for tests; the default is global fetch. */
  post?: (url: string, init: { method: string; headers: Record<string, string>; body: string }) => Promise<{ status: number; text: () => Promise<string> }>;
};

export const EMAILJS_ENDPOINT = 'https://api.emailjs.com/api/v1.0/email/send';

export class EmailSendError extends Error {
  readonly status: number;
  constructor(status: number) {
    super(`Email provider refused the message (${status})`);
    this.name = 'EmailSendError';
    this.status = status;
  }
}

export function createEmailJsTransport(options: EmailJsOptions): { configured: boolean; send: EmailTransport } {
  const endpoint = options.endpoint ?? EMAILJS_ENDPOINT;
  const post =
    options.post ??
    (async (url, init) => {
      const response = await fetch(url, init as RequestInit);
      return { status: response.status, text: () => response.text() };
    });

  const configured = Boolean(options.serviceId && options.templateId && options.publicKey && options.privateKey);

  return {
    configured,
    // The code is in the request body once, to EmailJS, over TLS. It is never
    // logged and never returned to a caller.
    send: async (message: VerificationEmail) => {
      const response = await post(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          service_id: options.serviceId,
          template_id: options.templateId,
          user_id: options.publicKey,
          accessToken: options.privateKey,
          template_params: {
            to_email: message.to,
            code: message.code,
            shop_name: message.shopName,
            app_name: options.appName ?? 'SimpleSales',
            expires_minutes: message.ttlMinutes,
          },
        }),
      });
      if (response.status < 200 || response.status >= 300) {
        throw new EmailSendError(response.status);
      }
    },
  };
}
