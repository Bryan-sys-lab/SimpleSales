-- Jobs were never used. Remove only the job tables; Open cost pools remain
-- supported for direct pooled-cost tracking and sale allocation.
DROP TABLE IF EXISTS "job_payments";
DROP TABLE IF EXISTS "job_costs";
DROP TABLE IF EXISTS "jobs";
