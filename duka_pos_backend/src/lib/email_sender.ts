/**
 * Verification email, sent through Cloudflare Email Service.
 *
 * Keys live only in this process; the app asks the server to send the mail.
 */

export type VerificationEmail = {
  to: string;
  code: string;
  shopName?: string;
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
    const subject = `${appName} — your verification code`;
    const logoUrl = process.env.NERVA_LOGO_URL ?? '';
    const logoHtml = logoUrl
      ? `<img src="${logoUrl}" alt="Nerva" width="120" style="display:block;margin-bottom:24px;" />`
      : `<p style="font-size:20px;font-weight:700;margin-bottom:24px;">Nerva</p>`;

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

    const html = `<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f5f5f5;font-family:sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#f5f5f5;padding:40px 0;">
    <tr><td align="center">
      <table width="480" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:8px;padding:40px;">
        <tr><td align="center" style="padding-bottom:8px;">
          ${logoHtml}
        </td></tr>
        <tr><td style="font-size:22px;font-weight:700;color:#111;padding-bottom:16px;">Confirm your account</td></tr>
        <tr><td style="font-size:15px;color:#444;padding-bottom:24px;">Hi,<br><br>You're almost there. Enter the verification code below to confirm your email address.</td></tr>
        <tr><td align="center" style="padding-bottom:24px;">
          <div style="display:inline-block;background:#f0f0f0;border-radius:8px;padding:20px 40px;font-size:32px;font-weight:800;letter-spacing:8px;color:#111;">${message.code}</div>
        </td></tr>
        <tr><td style="font-size:13px;color:#888;padding-bottom:24px;">Expires in ${message.ttlMinutes} minutes</td></tr>
        <tr><td style="font-size:13px;color:#888;padding-bottom:24px;">If you didn't request this code, no action is required. For your security, never share your verification code with anyone.</td></tr>
        <tr><td style="font-size:13px;color:#444;padding-bottom:8px;">Thank you for choosing <strong>${appName}</strong>.</td></tr>
        <tr><td style="font-size:12px;color:#aaa;"><em>This is an automated security email. Please do not reply.</em></td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`.trim();

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
