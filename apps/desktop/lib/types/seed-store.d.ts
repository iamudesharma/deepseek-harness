/** Deterministic archive transport for the desktop seed's pnpm store. */
/** Directory containing the seed's uncompressed pnpm store archives. */
export declare const SEED_STORE_ARCHIVE_DIR = "store-archives";
/** Manifest describing the deterministic pnpm store archive set. */
export declare const SEED_STORE_ARCHIVE_MANIFEST = "store-archives.json";
/**
 * Remove pnpm's registrations for projects that populated the seed store.
 * @param storeRoot - pnpm store directory included in the desktop seed.
 */
export declare function removePnpmProjectRegistrations(storeRoot: string): void;
/**
 * Merge a completely extracted seed store into Desktop's persistent pnpm store.
 * @param source - Verified temporary store extraction.
 * @param destination - Desktop-owned persistent pnpm store.
 */
export declare function mergePnpmStore(source: string, destination: string): void;
/**
 * Replace a prepared loose pnpm store with deterministic uncompressed archive shards.
 * @param seedRoot - seed directory that owns the archive output.
 * @param storeRoot - populated pnpm store to archive and remove after success.
 * @param shardCount - stable shard count used to limit update churn.
 */
export declare function archivePnpmStore(seedRoot: string, storeRoot: string, shardCount?: number): void;
/**
 * Validate and extract a packaged pnpm store archive set into an empty directory.
 * @param seedRoot - verified packaged seed directory.
 * @param destination - empty Desktop-owned temporary extraction directory.
 */
export declare function extractPnpmStoreArchives(seedRoot: string, destination: string): void;
//# sourceMappingURL=seed-store.d.ts.map