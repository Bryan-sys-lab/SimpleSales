/**
 * Verification email, sent through Cloudflare Email Service.
 *
 * Keys live only in this process; the app asks the server to send the mail.
 */
import {
  NERVA_LOGO_BASE64,
  NERVA_LOGO_CONTENT_ID,
  NERVA_LOGO_FILENAME,
  NERVA_LOGO_MIME_TYPE,
} from './nerva_logo';


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
    const logoHtml = `<img src="cid:${NERVA_LOGO_CONTENT_ID}" alt="Nerva" width="180" style="display:block;width:180px;height:auto;margin:0 auto 28px;border:0;" />`;
    const escapeHtml = (value: string) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
    const safeAppName = escapeHtml(appName);
    const safeCode = escapeHtml(message.code);

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
<body style="margin:0;padding:0;background:#f3f5f7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;color:#1b1d21;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f3f5f7;padding:32px 12px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border:1px solid #e5e7eb;border-radius:18px;padding:40px 36px;">
        <tr><td align="center" style="padding-bottom:4px;">
          ${logoHtml}
        </td></tr>
        <tr><td style="font-size:24px;line-height:1.25;font-weight:750;color:#111;padding-bottom:16px;">Confirm your account</td></tr>
        <tr><td style="font-size:15px;line-height:1.6;color:#4b5563;padding-bottom:24px;">Hi,<br><br>You're almost there. Enter the verification code below to confirm your email address.</td></tr>
        <tr><td align="center" style="padding:4px 0 24px;">
          <div style="display:inline-block;background:#f1f5f9;border:1px solid #e2e8f0;border-radius:12px;padding:18px 30px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:30px;line-height:1;font-weight:800;letter-spacing:8px;color:#111;">${safeCode}</div>
        </td></tr>
        <tr><td style="font-size:13px;line-height:1.5;color:#6b7280;padding-bottom:24px;">Expires in ${message.ttlMinutes} minutes.</td></tr>
        <tr><td style="font-size:13px;line-height:1.5;color:#6b7280;padding-bottom:24px;">If you didn't request this code, no action is required. For your security, never share your verification code with anyone.</td></tr>
        <tr><td style="font-size:13px;line-height:1.5;color:#374151;padding-bottom:8px;">Thank you for choosing <strong>${safeAppName}</strong>.</td></tr>
        <tr><td style="font-size:12px;line-height:1.5;color:#9ca3af;"><em>This is an automated security email. Please do not reply.</em></td></tr>
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
      attachments: [
        {
          content: NERVA_LOGO_BASE64,
          filename: NERVA_LOGO_FILENAME,
          type: NERVA_LOGO_MIME_TYPE,
          disposition: 'inline',
          contentId: NERVA_LOGO_CONTENT_ID,
        },
      ],
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
