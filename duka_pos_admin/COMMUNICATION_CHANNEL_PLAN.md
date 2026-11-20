# Internal communication channel — proposal for approval

**Status: proposal only. No communication feature is implemented by this plan.**

## Purpose

Give the company a traceable place to coordinate work without mixing messages into access controls, audit records, or customer data.

## Proposed structure

1. **Company announcements:** super admin broadcasts; department heads may publish only when granted `communications:announce`.
2. **Department rooms:** one room per department. Members see only their assigned department; managers can moderate their reporting line.
3. **Task discussions:** a private thread attached to a task and limited to its assignee, assigner, and their managers.
4. **Direct messages:** defer from the first release. They create broad retention, moderation, and discovery requirements with little operational benefit over task threads.

## Access and controls

- Permission scopes: `communications:read`, `communications:post`, `communications:moderate`, and `communications:announce`.
- Super admin can access, export, moderate, and change retention across all rooms.
- Department heads can add or remove only their direct reports. A manager of managers can manage rooms for their own reporting line.
- Invitations and permission changes remain in the administrator audit log.
- No external guests, public links, or anonymous posting in the first release.

## Message and data handling

- Messages support text and task links first. Attachments are deferred until malware scanning, file limits, and retention are agreed.
- Show sender, department, sent time, edit history, and read state where relevant. Do not silently edit or delete a message from the audit history.
- Proposed retention: 12 months for ordinary messages; preserve moderation and access events for 24 months. Make retention configurable by the super admin.
- Search is department-scoped for managers and company-wide for the super admin. Record administrative exports and moderation actions.
- Do not put shop customer data, payment credentials, passwords, or API keys in messages. Add a clear reminder in the composer.

## Delivery plan after approval

1. Confirm department membership, role scopes, retention, and whether read receipts are required.
2. Design message, room, membership, and audit records; decide delivery transport and offline behavior.
3. Build company announcements and department rooms, with permission checks on the server.
4. Add task threads and moderation, then validate access boundaries and mobile views.
5. Roll out to the super admin first, then selected department heads, with export and retention controls visible.

## Decisions requested

- Approve or revise the four room types and whether direct messages stay out of the first release.
- Confirm the proposed 12-month message and 24-month moderation-event retention.
- Confirm whether read receipts and attachments should be in the first release.
