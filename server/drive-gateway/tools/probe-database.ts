import type pg from "pg";
import { Database, type Db } from "../src/db.js";

/** Runner-only containment. Keep transaction ownership until the callback has settled. */
export class ProbeDatabase extends Database {
  private firstFailure?: Error & { code?: string };
  private observedErrors = 0;
  // EventEmitter callbacks are synchronous and never throw, await, or write evidence.
  private observeError = (error: Error & { code?: string }) => {
    this.firstFailure ??= error;
    this.observedErrors++;
  };

  constructor(pool: pg.Pool) {
    super(pool);
    pool.on("error", this.observeError);
  }

  assertHealthy() {
    if (this.firstFailure) throw this.firstFailure;
  }

  failureEvidence() {
    return this.firstFailure
      ? {
          sqlState: this.firstFailure.code ?? null,
          observedErrors: this.observedErrors,
        }
      : undefined;
  }

  override async transaction<T>(work: (db: Db) => Promise<T>): Promise<T> {
    this.assertHealthy();
    const db = await this.pool.connect();
    db.on("error", this.observeError);
    try {
      await db.query("begin");
      await db.query("set local lock_timeout = '3s'");
      await db.query("set local idle_in_transaction_session_timeout = '120s'");
      // Do not race work against a rejection: one accepted Drive call may still settle.
      const result = await work(db);
      this.assertHealthy();
      await db.query("commit");
      return result;
    } catch (error) {
      try {
        await db.query("rollback");
      } catch {
        /* A terminated connection cannot roll back again. */
      }
      throw this.firstFailure ?? error;
    } finally {
      if (this.firstFailure) {
        // Keep the nonthrowing listener on the destroyed client for trailing termination events.
        db.release(true);
      } else {
        db.release();
        db.removeListener("error", this.observeError);
      }
    }
  }
}
