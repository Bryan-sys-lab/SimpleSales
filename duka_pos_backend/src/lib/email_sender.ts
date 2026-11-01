/**
 * Verification email, sent through Cloudflare Email Service.
 *
 * Keys live only in this process; the app asks the server to send the mail.
 */

export type VerificationEmail = {
  to: string;
  code: string;
  shopName: string;
  ttlMinutes: number;
};

export type EmailTransport = (message: VerificationEmail) => Promise<void>;

export type CloudflareEmailOptions = {
  accountId: string;
  apiToken: string;
  from?: string;
  appName?: string;
  /** Injectable for tests; the default is global fetch. */
  post?: (url: string, init: { method: string; headers: Record<string, string>; body: string }) => Promise<{ status: number; text: () => Promise<string> }>;
};

export const CLOUDFLARE_EMAIL_ENDPOINT = (accountId: string) =>
  `https://api.cloudflare.com/client/v4/accounts/${accountId}/email/sending/send`;

export class EmailSendError extends Error {
  readonly status: number;
  constructor(status: number) {
    super(`Email provider refused the message (${status})`);
    this.name = 'EmailSendError';
    this.status = status;
  }
}

const DEFAULT_FROM = 'security@nerva.co.ke';

export function createCloudflareEmailTransport(options: CloudflareEmailOptions): { configured: boolean; send: EmailTransport } {
  const from = options.from || DEFAULT_FROM;
  const post =
    options.post ??
    (async (url, init) => {
      const response = await fetch(url, init as RequestInit);
      return { status: response.status, text: () => response.text() };
    });

  const configured = Boolean(options.accountId && options.apiToken && from);

  const buildBody = (message: VerificationEmail) => {
    const appName = options.appName ?? 'SimpleSales';
    const subject = `${appName} verification code`;
    const text = [
      `${appName}`,
      '',
      'Confirm your account',
      '',
      'Hi,',
      '',
      "You're almost there. Enter the verification code below to confirm your email address.",
      '',
      message.code,
      '',
      `Expires in ${message.ttlMinutes} minutes`,
      '',
      "If you didn't request this code, no action is required. For your security, never share your verification code with anyone.",
      '',
      `Thank you for choosing ${appName}.`,
      '',
      `${appName} Security`,
      '',
      'This is an automated security email. Please do not reply.',
    ].join('\n');

    const html = `
      <p><strong>${appName}</strong></p>
      <h2>Confirm your account</h2>
      <p>Hi,</p>
      <p>You're almost there. Enter the verification code below to confirm your email address.</p>
      <p><strong>${message.code}</strong></p>
      <p><strong>Expires in ${message.ttlMinutes} minutes</strong></p>
      <p>If you didn't request this code, no action is required. For your security, never share your verification code with anyone.</p>
      <p>Thank you for choosing <strong>${appName}</strong>.</p>
      <p><strong>${appName} Security</strong></p>
      <p><em>This is an automated security email. Please do not reply.</em></p>
    `.trim();

    return {
      to: message.to,
      from,
      subject,
      text,
      html,
    };
  };

  return {
    configured,
    send: async (message: VerificationEmail) => {
      const url = CLOUDFLARE_EMAIL_ENDPOINT(options.accountId);
      const response = await post(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${options.apiToken}`,
        },
        body: JSON.stringify(buildBody(message)),
      });
      if (response.status < 200 || response.status >= 300) {
        throw new EmailSendError(response.status);
      }
    },
  };
}

// Backwards-compatible alias while callers migrate.
export const createEmailJsTransport = createCloudflareEmailTransport;
