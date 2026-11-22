import { describe, expect, it, vi } from 'vitest';
import { deleteProfilePhoto, profilePhotoExists, type ProfileImageStorage } from '../lib/r2';

describe('profile image R2 binding', () => {
  it('checks whether an image exists through the bound bucket', async () => {
    const storage: ProfileImageStorage = {
      head: vi.fn(async () => null),
      delete: vi.fn(async () => undefined),
    };

    await expect(profilePhotoExists('profile-photos/user-1/photo.png', storage)).resolves.toBe(false);
    expect(storage.head).toHaveBeenCalledWith('profile-photos/user-1/photo.png');
  });

  it('deletes images through the bound bucket', async () => {
    const storage: ProfileImageStorage = {
      head: vi.fn(async () => null),
      delete: vi.fn(async () => undefined),
    };

    await deleteProfilePhoto('profile-photos/user-1/photo.png', storage);
    expect(storage.delete).toHaveBeenCalledWith('profile-photos/user-1/photo.png');
  });
});
