/** Filesystem ownership for the Electron-managed desktop installation. */
import { join } from 'node:path';
import { resolveDshHome } from '@deepseek-ai/dsh-home-paths';
/**
 * Resolve every Electron-owned path without changing the shared data roots.
 * @param dshHome - Harness home shared with npm-installed dsh.
 * @returns immutable desktop path set.
 */
export function resolveDesktopPaths(dshHome = resolveDshHome()) {
    const root = join(dshHome, 'desktop');
    const pnpm = join(root, 'pnpm');
    return {
        root,
        profile: join(dshHome, 'profiles', 'desktop'),
        staging: join(root, 'staging'),
        rollback: join(root, 'rollback', 'profile'),
        pending: join(root, 'pending.json'),
        lock: join(root, 'lock'),
        pnpm: {
            root: pnpm,
            store: join(pnpm, 'store'),
            cache: join(pnpm, 'cache'),
            state: join(pnpm, 'state'),
            config: join(pnpm, 'config'),
            home: join(pnpm, 'home'),
        },
    };
}
//# sourceMappingURL=paths.js.map