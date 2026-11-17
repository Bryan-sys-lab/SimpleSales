import { describe, expect, it } from 'vitest';
import { createCloudflareEmailTransport } from '../lib/email_sender';

describe('verification email branding', () => {
  it('embeds the Nerva logo inline and formats a selectable code', async () => {
    let sent: any;
    const transport = createCloudflareEmailTransport({
      accountId: 'account-1',
      apiToken: 'token-1',
      appName: 'SimpleSales',
      post: async (_url, init) => {
        sent = JSON.parse(init.body);
        return { status: 200, text: async () => '' };
      },
    });

    await transport.send({
      to: 'owner@example.com',
      code: '123456',
      shopName: 'Main shop',
      ttlMinutes: 10,
    });

    expect(sent.html).toContain('cid:nerva-logo');
    expect(sent.html).toContain('123456');
    expect(sent.html).toContain('font-family:ui-monospace');
    expect(sent.html).not.toContain('NERVA_LOGO_URL');
    expect(sent.to).toEqual(['owner@example.com']);
    expect(sent.attachments).toEqual([
      expect.objectContaining({
        filename: 'nerva-wordmark.png',
        type: 'image/png',
        disposition: 'inline',
        contentId: 'nerva-logo',
        content: expect.stringMatching(/^[A-Za-z0-9+/=]+$/),
      }),
    ]);
  });

  it('escapes dynamic email copy before putting it in HTML', async () => {
    let sent: any;
    const transport = createCloudflareEmailTransport({
      accountId: 'account-1',
      apiToken: 'token-1',
      appName: '<Shop>',
      post: async (_url, init) => {
        sent = JSON.parse(init.body);
        return { status: 200, text: async () => '' };
      },
    });
    await transport.send({ to: 'owner@example.com', code: '<1234>', ttlMinutes: 10 });
    expect(sent.html).toContain('&lt;Shop&gt;');
    expect(sent.html).toContain('&lt;1234&gt;');
    expect(sent.html).not.toContain('<Shop>');
  });

  it('includes the first-month voucher in both email formats', async () => {
    let sent: any;
    const transport = createCloudflareEmailTransport({
      accountId: 'account-1',
      apiToken: 'token-1',
      post: async (_url, init) => {
        sent = JSON.parse(init.body);
        return { status: 200, text: async () => '' };
      },
    });

    await transport.send({
      to: 'owner@example.com',
      code: '123456',
      ttlMinutes: 10,
      firstVoucherCode: 'SS-FIRST-MONTH',
    });

    expect(sent.text).toContain('SS-FIRST-MONTH');
    expect(sent.text).toContain('valid for one month');
    expect(sent.html).toContain('SS-FIRST-MONTH');
    expect(sent.html).toContain('First-month access');
  });
});
