import pg from "pg";
import { ApiError } from "./domain.js";
export type Db = pg.PoolClient;
export class Database {
  constructor(public pool: pg.Pool) {}
  async transaction<T>(work: (db: Db) => Promise<T>): Promise<T> {
    const db = await this.pool.connect();
    try {
      await db.query("begin");
      await db.query("set local lock_timeout = '3s'");
      await db.query("set local idle_in_transaction_session_timeout = '120s'");
      const result = await work(db);
      await db.query("commit");
      return result;
    } catch (e) {
      await db.query("rollback");
      throw e;
    } finally {
      db.release();
    }
  }
  async ready() {
    const { rows } = await this.pool
      .query(`select enabled and not has_function_privilege('authenticated',
      'public.claim_assignment_by_name(text)','execute') as enabled from firecheck_gateway.settings where id = true`);
    if (!rows[0]?.enabled) throw new ApiError(503, "GATEWAY_NOT_ACTIVATED");
  }
}
export async function member(db: Db, user: string, assignment: string) {
  const { rows } = await db.query(
    `select a.id,a.name,a.closed_remotely from public.assignments a
    join public.assignment_members m on m.assignment_id=a.id where a.id=$1 and m.enumerator_id=$2`,
    [assignment, user],
  );
  if (!rows[0]) throw new ApiError(403, "ASSIGNMENT_FORBIDDEN");
  return rows[0];
}
export async function supervisor(db: Db, user: string) {
  const { rowCount } = await db.query(
    "select 1 from firecheck_gateway.supervisors where user_id=$1",
    [user],
  );
  if (!rowCount) throw new ApiError(403, "SUPERVISOR_REQUIRED");
}
